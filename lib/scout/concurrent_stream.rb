require_relative 'indiferent_hash'

module AbortedStream
  attr_accessor :exception
  def self.setup(obj, exception = nil)
    obj.extend AbortedStream
    obj.exception = exception
  end
end

module ConcurrentStream
  attr_accessor :threads, :pids, :callback, :abort_callback, :filename, :joined, :aborted, :autojoin, :lock, :no_fail, :pair, :thread, :stream_exception, :log, :std_err, :next, :exit_status

  def self.setup(stream, options = {}, &block)
    threads, pids, callback, abort_callback, filename, autojoin, lock, no_fail, pair, next_stream = IndiferentHash.process_options options,
      :threads, :pids, :callback, :abort_callback, :filename, :autojoin, :lock, :no_fail, :pair, :next

    stream.extend ConcurrentStream unless ConcurrentStream === stream

    stream.threads ||= []
    stream.pids ||= []
    stream.threads.concat(Array === threads ? threads : [threads]) unless threads.nil?
    stream.pids.concat(Array === pids ? pids : [pids]) unless pids.nil? or pids.empty?
    stream.autojoin = autojoin unless autojoin.nil?
    stream.no_fail = no_fail unless no_fail.nil?
    stream.std_err = ""

    stream.next = next_stream unless next_stream.nil?
    stream.pair = pair unless pair.nil?

    callback = block if block_given?
    if callback
      if stream.callback
        old_callback = stream.callback
        stream.callback = Proc.new do
          old_callback.call
          callback.call
        end
      else
        stream.callback = callback
      end
    end

    if abort_callback
      if stream.abort_callback
        old_abort_callback = stream.abort_callback
        stream.abort_callback = Proc.new do
          old_abort_callback.call
          abort_callback.call
        end
      else
        stream.abort_callback = abort_callback
      end
    end

    stream.filename = filename if filename

    stream.lock = lock unless lock.nil?

    stream.aborted = false

    stream
  end

  def filename 
    @filename || self.inspect.split(":").last[0..-2]
  end

  def annotate(stream)
    ConcurrentStream.setup(stream, :threads => threads, :pids => pids, :callback => callback, :abort_callback => abort_callback, :filename => filename, :autojoin => autojoin, :lock => lock)
    stream
  end

  def clear
    @threads = @pids = @callback = @abort_callback = @joined = nil
  end

  def joined?
    @joined
  end

  def aborted?
    @aborted
  end

  def join_threads
    if @threads
      @threads.each do |t|
        next if t == Thread.current
        begin
          t.join
          if Process::Status === t.value
            if ! (t.value.success? || no_fail)

              if log
                msg = "Error joining #{self.filename || self.inspect}. Last log line: #{log}"
              else
                msg = "Error joining #{self.filename || self.inspect}"
              end

              raise ConcurrentStreamProcessFailed.new t.pid, msg, self
            end
          end
        rescue Exception
          if no_fail
            Log.low "Not failing on exception joining thread in ConcurrenStream - #{filename} - #{$!.message}"
          else
            Log.low "Exception joining thread in ConcurrenStream #{Log.fingerprint self} - #{Log.fingerprint t} - #{$!.message}"
            stream_raise_exception $!
          end
        end
      end
    end
    @threads = []
  end

  def join_pids
    if @pids and @pids.any?
      @pids.each do |pid|
        begin
          Process.waitpid(pid, Process::WUNTRACED)
          self.exit_status = $?.exitstatus
          stream_raise_exception ConcurrentStreamProcessFailed.new(pid, "Error in waitpid", self) unless $?.success? or no_fail
        rescue Errno::ECHILD
        end
      end
      @pids = []
    end
  end

  def join_callback
    if @callback and not joined?
      begin
        @callback.call
      ensure
        @callback = nil
      end
    end
  end

  def join
    begin
      join_threads
      join_pids
      raise stream_exception if stream_exception
      join_callback
      close unless closed?
    ensure
      @joined = true
      begin
        lock.unlock if lock && lock.locked?
      rescue
        Log.exception $!
      end
      raise stream_exception if stream_exception
    end
  end

  def abort_threads(exception = nil)
    return unless @threads and @threads.any?
    name = Log.fingerprint(Thread.current)
    name += " - file:#{filename}" if filename
    Log.low "Aborting threads (#{name}) - #{@threads.collect{|t| Log.fingerprint(t) } * ", "}"

    threads = @threads.dup
    @threads.clear
    threads.each do |t|
      next if t == Thread.current
      next if t["aborted"]
      t["aborted"] = true
      exception = exception.nil? ? Aborted.new : exception
      Log.debug "Aborting thread #{Log.fingerprint(t)} with exception: #{exception}"
      t.raise(exception)
      t.join
    end
  end

  def abort_pids
    @pids.each do |pid|
      begin
        Log.low "Killing PID #{pid} in ConcurrentStream #{filename}"
        Process.kill :INT, pid
      rescue Errno::ESRCH
      end
    end if @pids
    @pids = []
  end

  def abort(exception = nil)
    self.stream_exception ||= exception
    if @aborted
      Log.medium "Already aborted stream #{Log.fingerprint self} [#{@aborted}]"
      return
    else
      Log.medium "Aborting stream #{Log.fingerprint self} [#{@aborted}]"
    end
    AbortedStream.setup(self, exception)
    @aborted = true
    begin
      @abort_callback.call exception if @abort_callback

      abort_threads(exception)
      abort_pids

      @callback = nil
      @abort_callback = nil

      if @pair && @pair.respond_to?(:abort) && ! @pair.aborted?
        Log.medium "Aborting pair stream #{Log.fingerprint self}: #{Log.fingerprint @pair }"
        @pair.abort exception
      end
    ensure
      close unless closed?

      if lock and lock.locked?
        lock.unlock
      end
    end
  end

  def close(*args)
    if autojoin
      begin
        super(*args)
      rescue
        self.abort
        self.join
        stream_raise_exception $!
      ensure
        self.join if ! @stream_exception && (self.closed? || self.eof?)
      end
    else
      begin
        super(*args)
      rescue IOError
      end unless self.closed?
    end
  end

  def read(*args)
    begin
      super(*args)
    rescue Exception
      @stream_exception ||= $!
      raise @stream_exception
    ensure
      if ! @stream_exception && autojoin && ! closed?
        begin
          done = eof?
        rescue Exception
          self.abort($!)
          raise $!
        end
        close if done
      end
      join if autojoin && (closed? || @stream_exception)
    end
  end

  def add_callback(&block)
    old_callback = callback
    @callback = Proc.new do
      old_callback.call if old_callback
      block.call
    end
  end

  def stream_raise_exception(exception)
    self.stream_exception = exception
    threads.each do |thread|
      thread.raise exception
    end
    self.abort
  end

  def self.process_stream(stream, close: true, join: true, message: "process_stream", **kwargs, &block)
    ConcurrentStream.setup(stream, **kwargs)
    begin
      begin
        yield
      ensure
        stream.close if close && stream.respond_to?(:close) && ! (stream.respond_to?(:closed?) && stream.closed?)
        stream.join if join && stream.respond_to?(:join) && ! stream.joined?
      end
    rescue Aborted
      Log.low "Aborted #{message}: #{$!.message}"
      stream.abort($!) if stream.respond_to?(:abort) && ! stream.aborted?
      raise $!
    rescue Exception
      Log.low "Exception #{message}: #{$!.message}"
      stream.abort($!) if stream.respond_to?(:abort) && ! stream.aborted?
      raise $!
    end
  end
end
