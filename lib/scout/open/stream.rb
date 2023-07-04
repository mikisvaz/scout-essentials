module Open
  BLOCK_SIZE = 1024 * 8

  class << self
    attr_accessor :sensible_write_lock_dir

    def sensible_write_lock_dir
      @sensible_write_lock_dir ||= Path.setup("tmp/sensible_write_locks").find
    end
  end

  class << self
    attr_accessor :sensible_write_dir
    def sensible_write_dir
      @sensible_write_dir ||= Path.setup("tmp/sensible_write").find
    end
  end

  def self.consume_stream(io, in_thread = false, into = nil, into_close = true, &block)
    return if Path === io
    return unless io.respond_to? :read

    if io.respond_to? :closed? and io.closed?
      io.join if io.respond_to? :join
      return
    end

    if in_thread
      consumer_thread = Thread.new(Thread.current) do |parent|
        Thread.current["name"] = "Consumer #{Log.fingerprint io}"
        Thread.current.report_on_exception = false
        consume_stream(io, false, into, into_close)
      end

      io.threads.push(consumer_thread) if io.respond_to?(:threads)
      Thread.pass until consumer_thread["name"]

      consumer_thread
    else
      if into
        Log.low "Consuming stream #{Log.fingerprint io} -> #{Log.fingerprint into}"
      else
        Log.low "Consuming stream #{Log.fingerprint io}"
      end

      begin
        into = into.find if Path === into

        if String === into
          dir = File.dirname(into)
          Open.mkdir dir unless File.exist?(dir)
          into_path, into = into, File.open(into, 'w')
        end

        into_close = false unless into.respond_to? :close

        while c = io.read(BLOCK_SIZE)
          into << c if into
          last_c = c if c
          break if io.closed?
        end

        io.join if io.respond_to? :join
        io.close unless io.closed?
        into.join if into and into_close and into.respond_to?(:joined?) and not into.joined?
        into.close if into and into_close and not into.closed?
        block.call if block_given?

        last_c
      rescue Aborted
        Thread.current["exception"] = true
        Log.low "Consume stream Aborted #{Log.fingerprint io} into #{into_path || into}"
        io.abort $! if io.respond_to? :abort
        into.close if into.respond_to?(:closed?) && ! into.closed?
        FileUtils.rm into_path if into_path and File.exist?(into_path)
      rescue Exception
        Thread.current["exception"] = true
        Log.low "Consume stream Exception reading #{Log.fingerprint io} into #{into_path || into} - #{$!.message}"
        exception = (io.respond_to?(:stream_exception) && io.stream_exception) ? io.stream_exception : $!
        io.abort exception if io.respond_to? :abort
        into.close if into.respond_to?(:closed?) && ! into.closed?
        into_path = into if into_path.nil? && String === into
        if into_path and File.exist?(into_path)
          FileUtils.rm into_path
        end
        raise exception
      end
    end
  end

  def self.sensible_write(path, content = nil, options = {}, &block)
    force = IndiferentHash.process_options options, :force

    if File.exist?(path) and not force
      Open.consume_stream content
      return
    end

    lock_options = IndiferentHash.pull_keys options.dup, :lock
    lock_options = lock_options[:lock] if Hash === lock_options[:lock]
    tmp_path = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_dir})
    tmp_path_lock = TmpFile.tmp_for_file(path, {:dir => Open.sensible_write_lock_dir})

    tmp_path_lock = nil if FalseClass === options[:lock]

    Open.lock tmp_path_lock, lock_options do

      if File.exist? path and not force
        Log.warn "Path exists in sensible_write, not forcing update: #{ path }"
        Open.consume_stream content
      else
        FileUtils.mkdir_p File.dirname(tmp_path) unless File.directory?(File.dirname(tmp_path))
        FileUtils.rm_f tmp_path if File.exist? tmp_path
        Log.low "Sensible write stream #{Log.fingerprint content} -> #{Log.fingerprint path}" if IO === content
        begin
          case
          when block_given?
            File.open(tmp_path, 'wb', &block)
          when String === content
            File.open(tmp_path, 'wb') do |f| f.write content end
          when (IO === content or StringIO === content or File === content)
            Open.write(tmp_path) do |f|
              while block = content.read(BLOCK_SIZE)
                f.write block
                break if content.closed?
              end
            end
          else
            File.open(tmp_path, 'wb') do |f|  end
          end

          begin
            Misc.insist do
              Open.mv tmp_path, path, lock_options
            end
          rescue Exception
            raise $! unless File.exist? path
          end

          Open.touch path if File.exist? path
          content.join if content.respond_to?(:join) and not Path === content and not (content.respond_to?(:joined?) && content.joined?)

          Open.notify_write(path)
        rescue Aborted
          Log.low "Aborted sensible_write -- #{ Log.reset << path }"
          content.abort if content.respond_to? :abort
          Open.rm path if File.exist? path
        rescue Exception
          exception = (AbortedStream === content and content.exception) ? content.exception : $!
          Log.low "Exception in sensible_write: [#{Process.pid}] #{exception.message} -- #{ path }"
          content.abort(exception) if content.respond_to? :abort
          Open.rm path if File.exist? path
          raise exception
        rescue
          raise $!
        ensure
          FileUtils.rm_f tmp_path if File.exist? tmp_path
          if Lockfile === lock_options[:lock] and lock_options[:lock].locked?
            lock_options[:lock].unlock
          end
        end
      end
    end
  end

  PIPE_MUTEX = Mutex.new

  OPEN_PIPE_IN = []
  def self.pipe
    OPEN_PIPE_IN.delete_if{|pipe| pipe.closed? }
    res = PIPE_MUTEX.synchronize do
      sout, sin = IO.pipe
      OPEN_PIPE_IN << sin

      [sout, sin]
    end
    Log.low{"Creating pipe #{[Log.fingerprint(res.last), Log.fingerprint(res.first)] * " -> "}"}
    res
  end

  def self.with_fifo(path = nil, clean = true, &block)
    begin
      erase = path.nil?
      path = TmpFile.tmp_file if path.nil?
      File.rm path if clean && File.exist?(path)
      File.mkfifo path
      yield path
    ensure
      FileUtils.rm path if erase && File.exist?(path)
    end
  end

  def self.release_pipes(*pipes)
    PIPE_MUTEX.synchronize do
      pipes.flatten.each do |pipe|
        pipe.close unless pipe.closed?
      end
    end
  end

  def self.purge_pipes(*save)
    PIPE_MUTEX.synchronize do
      OPEN_PIPE_IN.each do |pipe|
        next if save.include? pipe
        pipe.close unless pipe.closed?
      end
    end
  end

  def self.open_pipe(do_fork = false, close = true)
    raise "No block given" unless block_given?

    sout, sin = Open.pipe

    if do_fork

      pid = Process.fork {
        begin
          purge_pipes(sin)
          sout.close

          yield sin
          sin.close if close and not sin.closed?

        rescue Exception
          Log.exception $!
          Kernel.exit!(-1)
        end
        Kernel.exit! 0
      }
      sin.close

      ConcurrentStream.setup sout, :pids => [pid]
    else

      ConcurrentStream.setup sin, :pair => sout
      ConcurrentStream.setup sout, :pair => sin

      thread = Thread.new do
        begin
          ConcurrentStream.process_stream(sin, :message => "Open pipe") do
            Thread.current.report_on_exception = false
            Thread.current["name"] = "Pipe input #{Log.fingerprint sin} => #{Log.fingerprint sout}"

            yield sin
          end
        end
      end

      sin.threads = [thread]
      sout.threads = [thread]

      Thread.pass until thread["name"]
    end

    sout
  end

  def self.tee_stream_thread_multiple(stream, num = 2)
    in_pipes = []
    out_pipes = []
    num.times do
      sout, sin = Open.pipe
      in_pipes << sin
      out_pipes << sout
    end

    Log.low("Tee stream #{Log.fingerprint stream} -> #{Log.fingerprint out_pipes}")

    filename = stream.filename if stream.respond_to? :filename

    splitter_thread = Thread.new(Thread.current) do |parent|
      begin
        Thread.current.report_on_exception = false
        Thread.current["name"] = "Splitter #{Log.fingerprint stream}"

        skip = [false] * num
        while block = stream.read(BLOCK_SIZE)

          in_pipes.each_with_index do |sin,i|
            begin
              sin.write block
            rescue IOError
              Log.warn("Tee stream #{i} #{Log.fingerprint stream} IOError: #{$!.message} (#{Log.fingerprint sin})");
              skip[i] = true
            rescue
              Log.warn("Tee stream #{i} #{Log.fingerprint stream} Exception: #{$!.message} (#{Log.fingerprint sin})");
              raise $!
            end unless skip[i]
          end
          break if stream.closed?
        end

        stream.join if stream.respond_to? :join
        in_pipes.first.close unless in_pipes.first.closed?
      rescue Aborted, Interrupt
        stream.abort if stream.respond_to?(:abort) && ! stream.aborted?
        out_pipes.reverse.each do |sout|
          sout.threads.delete(Thread.current)
          begin
            sout.abort($!) if sout.respond_to?(:abort) && ! sout.aborted?
          rescue
          end
        end
        in_pipes.each do |sin|
          sin.close unless sin.closed?
        end
        Log.low "Tee aborting #{Log.fingerprint stream}"
        raise $!
      rescue Exception
        begin
          stream.abort($!) if stream.respond_to?(:abort) && ! stream.aborted?
          out_pipes.reverse.each do |sout|
            sout.threads.delete(Thread.current)
            begin
              sout.abort($!) if sout.respond_to?(:abort) && ! sout.aborted?
            rescue
            end
          end
          in_pipes.each do |sin|
            sin.close unless sin.closed?
          end
          Log.low "Tee exception #{Log.fingerprint stream}"
        rescue
        ensure
          begin
            in_pipes.each do |sin|
              sin.close unless sin.closed?
            end
          ensure
            raise $!
          end
        end
      end
    end

    Thread.pass until splitter_thread["name"]

    main_pipe = out_pipes.first

    ConcurrentStream.setup(main_pipe, :threads => [splitter_thread], :filename => filename, :autojoin => true)

    out_pipes[1..-1].each do |sout|
      ConcurrentStream.setup sout, :filename => filename, :threads => [splitter_thread]
    end

    main_pipe.callback = proc do
      begin
        stream.join if stream.respond_to?(:join) && ! stream.joined?
        in_pipes[1..-1].each do |sin|
          sin.close unless sin.closed?
        end
      rescue
        main_pipe.abort_callback.call($!)
        raise $!
      end
    end

    main_pipe.abort_callback = proc do |exception|
      stream.abort(exception)
      out_pipes[1..-1].each do |sout|
        sout.abort(exception)
      end
    end

    out_pipes
  end

  def self.tee_stream_thread(stream)
    tee_stream_thread_multiple(stream, 2)
  end

  def self.tee_stream(stream)
    tee_stream_thread(stream)
  end

  def self.read_stream(stream, size)
    str = nil
    Thread.pass while IO.select([stream],nil,nil,1).nil?
    while not str = stream.read(size)
      IO.select([stream],nil,nil,1)
      Thread.pass
      raise ClosedStream if stream.eof?
    end

    while str.length < size
      raise ClosedStream if stream.eof?
      IO.select([stream],nil,nil,1)
      if new = stream.read(size-str.length)
        str << new
      end
    end
    str
  end

  def self.read_stream(stream, size)
    str = ""
    while str.length < size
      missing = size - str.length
      more = stream.read(missing)
      str << more
    end
    str
  end

  def self.sort_stream(stream, header_hash: "#", cmd_args: "-u", memory: false)
    sout = Open.open_pipe do |sin|
      ConcurrentStream.process_stream(stream) do
        line = stream.gets
        while line && line.start_with?(header_hash) do
          sin.puts line
          line = stream.gets
        end

        line_stream = Open.open_pipe do |line_stream_in|
          line_stream_in.puts line if line
          Open.consume_stream(stream, false, line_stream_in)
        end
        Log.low "Sub-sort stream #{Log.fingerprint stream} -> #{Log.fingerprint line_stream}"

        if memory
          line_stream.read.split("\n").sort.each do |line|
            sin.puts line
          end
        else
          io = CMD.cmd("env LC_ALL=C sort #{cmd_args || ""}", :in => line_stream, :pipe => true)
          Open.consume_stream(io, false, sin)
        end
      end
    end
    Log.low "Sort #{Log.fingerprint stream} -> #{Log.fingerprint sout}"
    sout
  end

  #def self.sort_stream(stream, header_hash = "#", cmd_args = "-u")
  #  StringIO.new stream.read.split("\n").sort.uniq * "\n"
  #end

  def self.collapse_stream(s, line: nil, sep: "\t", header: nil, &block)
    sep ||= "\t"
    Open.open_pipe do |sin|

      sin.puts header if header

      line ||= s.gets

      current_parts = []
      while line
        key, *parts = line.chomp.split(sep, -1)
        case
        when key.nil?
        when current_parts.nil?
          current_parts = parts
          current_key = key
        when current_key == key
          parts.each_with_index do |part,i|
            if current_parts[i].nil?
              current_parts[i] = "|" << part
            else
              current_parts[i] = current_parts[i] << "|" << part
            end
          end

          (parts.length..current_parts.length-1).to_a.each do |pos|
            current_parts[pos] = current_parts[pos] << "|" << ""
          end
        when current_key.nil?
          current_key = key
          current_parts = parts
        when current_key != key
          if block_given?
            res = block.call(current_parts)
            sin.puts [current_key, res] * sep
          else
            sin.puts [current_key, current_parts].flatten * sep
          end
          current_key = key
          current_parts = parts
        end
        line = s.gets
      end

      if block_given?
        res = block.call(current_parts)
        sin.puts [current_key, res] * sep
      else
        sin.puts [current_key, current_parts].flatten * sep
      end unless current_key.nil?
    end
  end
end
