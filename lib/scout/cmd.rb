require_relative 'indiferent_hash'
require_relative 'concurrent_stream'
require_relative 'log'
require_relative 'exceptions'
require_relative 'open/stream'
require 'stringio'
require 'open3'

module CMD

  # Grace period, in seconds, between sending :INT and escalating to :KILL
  # when a command exceeds its :timeout option
  TIMEOUT_KILL_GRACE = 1.0

  # ScoutCoder: exception raised by CMD.cmd when a command exceeds its
  # :timeout option. It subclasses ProcessFailed, so generic rescue clauses
  # for ProcessFailed also catch it. In pipe mode the stream is aborted with
  # this exception (ConcurrentStream#abort), so consumers observe it through
  # ConcurrentStream#stream_raise_exception when reading or joining the
  # returned stream.
  class Timeout < ProcessFailed
    attr_reader :command, :timeout
    def initialize(pid = Process.pid, command = nil, timeout = nil)
      @command = command
      @timeout = timeout
      super(pid, "command '#{command}' exceeded timeout of #{timeout} seconds")
    end
  end

  TOOLS = IndiferentHash.setup({})
  def self.tool(tool, claim = nil, test = nil, cmd = nil, &block)
    TOOLS[tool] = [claim, test, block, cmd]
  end

  def self.conda(tool, env = nil, channel = 'bioconda')
    if env
      CMD.cmd("bash -l -c '(conda activate #{env} && conda install #{tool} -c #{channel})'")
    else
      CMD.cmd("bash -l -c 'conda install #{tool} -c #{channel}'")
    end
  end


  def self.get_tool(tool)
    return tool.to_s unless TOOLS[tool]

    @@init_cmd_tool ||= IndiferentHash.setup({})

    claim, test, block, cmd = TOOLS[tool]
    cmd = tool.to_s if cmd.nil?

    if !@@init_cmd_tool[tool]

      begin
        if test
          CMD.cmd(test + " ")
        else
          CMD.cmd("bash -c 'command -v #{cmd}'")
        end
      rescue
        if claim
          claim.produce
        else
          res = block.call
          if Hash === res
            Resource.install res, tool.to_s
          end
        end
      end
      version_txt = ""
      version = nil
      ["--version", "-version", "--help", ""].each do |f|
        begin
          version_txt += CMD.cmd("#{cmd} #{f} 2>&1", :nofail => true).read
          version = CMD.scan_version_text(version_txt, tool)
          break if version
        rescue
          Log.exception $!
        end
      end

      @@init_cmd_tool[tool] = version || true

      return cmd if cmd
    end

    cmd
  end

  def self.scan_version_text(text, cmd = nil)
    cmd = "NOCMDGIVE" if cmd.nil? || cmd.empty?
    text = Misc.fixutf8 text
    text.split("\n").each do |line|
      next unless line =~ /\W#{cmd}\W/i
      m = line.match(/(v(?:\d+\.)*\d+(?:-[a-z_]+)?)/i)
      return m[1] if m
      m = line.match(/((?:\d+\.)*\d+(?:-[a-z_]+)?v)/i)
      return m[1] if m
      next unless line =~ /\Wversion\W/i
      m = line.match(/((?:\d+\.)*\d+(?:-[a-z_]+)?)/i)
      return m[1] if m
    end
    m = text.match(/(?:version.*?|#{cmd}.*?|#{cmd.to_s.split(/[-_.]/).first}.*?|v)((?:\d+\.)*\d+(?:-[a-z_]+)?)/i)
    return m[1] if m
    m = text.match(/(?:#{cmd}.*(v.*|.*v))/i)
    return m[1] if m
    nil
  end
  def self.versions
    return {} unless defined? @@init_cmd_tool
    @@init_cmd_tool.select{|k,v| v =~ /\d+\./ }
  end

  def self.bash(cmd)
    cmd = %Q(bash -l <<EOF\n#{cmd}\nEOF\n)
    CMD.cmd(cmd, :autojoin => true)
  end

  def self.process_cmd_options(options = {})
    add_dashes = IndiferentHash.process_options options, :add_option_dashes

    string = ""
    options.each do |option, value|
      raise "Invalid option key: #{option.inspect}" if option.to_s !~ /^[a-z_0-9\-=.]+$/i
      #raise "Invalid option value: #{value.inspect}" if value.to_s.include? "'"
      value = value.gsub("'","\\'") if value.to_s.include? "'"

      option = "--" << option.to_s if add_dashes and option.to_s[0] != '-'

      case
      when value.nil? || FalseClass === value
        next
      when TrueClass === value
        string += "#{option} "
      else
        if option.to_s.chars.to_a.last == "="
          string += "#{option}'#{value}' "
        else
          string += "#{option} '#{value}' "
        end
      end
    end

    string.strip
  end

  # ScoutCoder: process_cmd_options_array mirrors process_cmd_options but
  # returns an array of separate argument strings instead of a single shell
  # string, suitable for the no-shell array form of Open3.popen3
  def self.process_cmd_options_array(options = {})
    add_dashes = IndiferentHash.process_options options, :add_option_dashes

    result = []
    options.each do |option, value|
      raise "Invalid option key: #{option.inspect}" if option.to_s !~ /^[a-z_0-9\-=.]+$/i

      option = "--" << option.to_s if add_dashes and option.to_s[0] != '-'

      case
      when value.nil? || FalseClass === value
        next
      when TrueClass === value
        result << option.to_s
      else
        if option.to_s.chars.to_a.last == "="
          result << "#{option}#{value}"
        else
          result << option.to_s
          result << value.to_s
        end
      end
    end

    result
  end

  def self.cmd(tool, cmd = nil, options = {}, &block)
    options, cmd = cmd, nil if Hash === cmd

    options    = IndiferentHash.add_defaults options, :stderr => Log::DEBUG
    in_content = options.delete(:in)
    stderr     = options.delete(:stderr)
    sudo       = options.delete(:sudo)
    post       = options.delete(:post)
    pipe       = options.delete(:pipe)
    log        = options.delete(:log)
    no_fail    = options.delete(:no_fail)
    no_fail    = options.delete(:nofail) if no_fail.nil?
    no_wait    = options.delete(:no_wait)
    xvfb       = options.delete(:xvfb)
    bar        = options.delete(:progress_bar)
    save_stderr = options.delete(:save_stderr)
    autojoin   = options.delete(:autojoin)
    autojoin   = no_wait if autojoin.nil?
    timeout    = options.delete(:timeout)

    dont_close_in  = options.delete(:dont_close_in)

    log = true if log.nil?

    array_mode = Array === tool

    if array_mode
      cmd_array = tool.dup
      cmd_array << cmd if cmd.is_a?(String) && !cmd.empty?

      case xvfb
      when TrueClass
        cmd_array = ["xvfb-run", "--server-args=-screen 0 1024x768x24", "--auto-servernum"] + cmd_array
      when String
        cmd_array = ["xvfb-run", "--server-args=#{xvfb}", "--auto-servernum", "--server-num=1"] + cmd_array
      end

      if stderr == true
        stderr = Log::HIGH
      end

      cmd_array += process_cmd_options_array options

      cmd_array = ["sudo"] + cmd_array if sudo

      # Build cmd string for logging/error messages
      cmd = cmd_array.map { |e| e.to_s.include?(' ') ? "'#{e}'" : e.to_s }.join(' ')
    else
      if cmd.nil? && ! Symbol === tool
        cmd = tool
      else
        tool = get_tool(tool)
        if cmd.nil?
          cmd = tool
        else
          cmd = tool + ' ' + cmd
        end

      end

      case xvfb
      when TrueClass
        cmd = "xvfb-run --server-args='-screen 0 1024x768x24' --auto-servernum #{cmd}"
      when String
        cmd = "xvfb-run --server-args='#{xvfb}' --auto-servernum --server-num=1 #{cmd}"
      when String
      end

      if stderr == true
        stderr = Log::HIGH
      end

      cmd_options = process_cmd_options options
      if cmd =~ /'\{opt\}'/
        cmd = cmd.sub('\'{opt}\'', cmd_options)
      else
        cmd += " " + cmd_options
      end

      if sudo
        cmd = "sudo " + cmd
      end
    end

    in_content = StringIO.new in_content if String === in_content

    sin, sout, serr, wait_thr = begin
                                  if array_mode
                                    Open3.popen3(ENV, *cmd_array)
                                  else
                                    Open3.popen3(ENV, cmd)
                                  end
                                rescue
                                  Log.warn $!.message
                                  raise ProcessFailed, nil, cmd unless no_fail
                                  return
                                end
    pid = wait_thr.pid

    if Log.severity >= 2
      Log.medium("CMD [#{pid}] #{Log.fingerprint(cmd)}")
    else
      Log.debug("CMD [#{pid}] #{cmd.strip}")
    end

    # ScoutCoder: :timeout support.  A watchdog thread starts a counter
    # (deadline) for the command; if the process is still running when the
    # timeout is reached it kills it and raises CMD::Timeout.
    #
    # In pipe mode the exception is routed through ConcurrentStream#abort:
    # it is stored in stream_exception, the stream is aborted (which
    # interrupts any consumer blocked reading from it, kills the process and
    # clears the pid list) and it is re-raised when the consumer reads or
    # joins the stream.  In non-pipe mode the watchdog raises directly in the
    # thread running CMD.cmd, unblocking its read, and the internal stream is
    # aborted in the rescue below.
    #
    # The watchdog is deliberately NOT registered in sout.threads, so it never
    # delays a normal join, and it always ends up reaping the pid (see
    # reap_timeout_pid below) to avoid leaving a zombie behind when the
    # Process::Waiter thread is interrupted by the abort.
    timeout_thread = nil
    timeout_exception = nil
    timed_out = false
    if Numeric === timeout && timeout > 0
      timeout_exception = Timeout.new(pid, cmd, timeout)
      caller_thread = Thread.current

      # The helper threads are interrupted with the timeout exception when
      # the command is killed; do not report that as a thread crash
      wait_thr.report_on_exception = false

      # Kill the process: :INT first, escalate to :KILL after a grace period,
      # and reap it so that no zombie is left behind.  Works whether or not
      # the Process::Waiter thread is still alive: whoever waits first reaps
      # the pid and the other one gets Errno::ECHILD.
      reap_timeout_pid = Proc.new do
        begin
          Process.kill(:INT, pid)
        rescue Errno::ESRCH
        end

        grace_end = Time.now + TIMEOUT_KILL_GRACE
        reaped = false
        while Time.now < grace_end
          begin
            reaped = ! Process.waitpid(pid, Process::WNOHANG).nil?
            break if reaped
          rescue Errno::ECHILD
            reaped = true
            break
          end
          sleep 0.05
        end

        unless reaped
          begin
            Process.kill(:KILL, pid)
          rescue Errno::ESRCH
          end
          begin
            Process.waitpid(pid)
          rescue Errno::ECHILD
          end
        end
      end

      timeout_thread = Thread.new do
        Thread.current["name"] = "CMD timeout: [#{pid}] #{cmd}"
        Thread.current.report_on_exception = false

        begin
          # Counter: deadline of the command, measured from spawn time.  The
          # extra join(0) discards the boundary race in which the process
          # finished exactly at the deadline
          if wait_thr.join(timeout).nil? && wait_thr.join(0).nil?
            timed_out = true
            Log.low "CMD: [#{pid}] #{cmd} timed out after #{timeout} seconds. Killing"

            if pipe
              # Store the exception and abort the stream BEFORE the pid is
              # gone, so that consumers blocked on a read are interrupted and
              # get the exception instead of a plain EOF.  abort (rather than
              # stream_raise_exception) is used so the helper threads are
              # interrupted with the timeout exception itself: if they died
              # with any other exception, joining them would overwrite
              # stream_exception and hide the timeout
              sout.abort timeout_exception if sout.respond_to?(:abort) && ! sout.joined?
              reap_timeout_pid.call
            else
              # Unblock the thread running CMD.cmd immediately; the kill and
              # the clean-up of the internal stream happen in its rescue path
              # and in reap_timeout_pid below
              caller_thread.raise timeout_exception
              reap_timeout_pid.call
            end
          end
        rescue Exception
          # Never let the watchdog crash the process
          Log.exception $!
        end
      end
      Thread.pass until timeout_thread["name"]
    end

    if in_content.respond_to?(:read)
      in_thread = Thread.new(Thread.current) do |parent|
        begin
          Thread.current.report_on_exception = false if no_fail || timeout_exception
          Thread.current["name"] = "CMD in"
          while c = in_content.read(Open::BLOCK_SIZE)
            sin << c
            break if in_content.closed?
          end

          sin.close  unless sin.closed?
          sin.join if sin.respond_to? :join

          unless dont_close_in
            in_content.close unless in_content.closed?
            in_content.join if in_content.respond_to? :join
          end
        rescue Exception
          unless no_fail || Aborted === $! || Timeout === $!
            Log.error "Error in CMD  [#{pid}] #{cmd}: #{$!.message}"
          end
          sin.close  unless sin.closed?
          sin.join if sin.respond_to? :join
          raise $!
        end
      end
      Thread.pass until in_thread["name"]
    else
      in_thread = nil
      sin.close
    end

    pids = [pid]

    if pipe

      ConcurrentStream.setup sout, :pids => pids, :autojoin => autojoin, :no_fail => no_fail

      sout.callback = post if post

      if (Integer === stderr and log) || bar
        err_thread = Thread.new do
          Thread.current["name"] = "Error log: [#{pid}] #{ cmd }"
          Thread.current.report_on_exception = false
          begin
            while line = serr.gets
              bar.process(line) if bar
              sout.log = line
              sout.std_err << line if save_stderr
              Log.log "STDERR [#{pid}]: " +  line, stderr if log
            end
            serr.close
          rescue Aborted
            # The stream was aborted (e.g. by a :timeout): stop silently, the
            # consumer of sout gets the real exception from the stream
            serr.close unless serr.closed?
          rescue
            # When the stream is being aborted (e.g. by a :timeout) the
            # consumer gets the real exception from the stream itself
            Log.exception $! unless sout.aborted?
            raise $!
          end
        end
      else
        err_thread = Open.consume_stream(serr, true)
      end

      sout.threads = [in_thread, err_thread, wait_thr].compact

      sout
    else
      err = ""
      if bar
        err_thread = Thread.new do
          Thread.current.report_on_exception = false
          begin
            while not serr.eof?
              line = serr.gets
              bar.process(line)
              err << line if Integer === stderr and log
            end
            serr.close
          rescue Exception
            # Interrupted while the stream is aborted (e.g. by a :timeout);
            # the CMD.cmd thread surfaces the real exception
            serr.close unless serr.closed?
          end
        end
      elsif log and Integer === stderr
        err_thread = Thread.new do
          Thread.current.report_on_exception = false
          begin
            while not serr.eof?
              err += serr.gets
            end
            serr.close
          rescue Exception
            serr.close unless serr.closed?
          end
        end
      else
        Open.consume_stream(serr, true)
        err_thread = nil
      end

      ConcurrentStream.setup sout, :pids => pids, :threads => [in_thread, err_thread].compact, :autojoin => autojoin, :no_fail => no_fail

      begin
        out = StringIO.new sout.read
        status = wait_thr.value

        # Settle the watchdog decision: if the process finished right at the
        # deadline the watchdog may still be deciding, so wait for it before
        # reporting success.  A real timeout raises directly in this thread
        # and is handled by the rescue below.
        timeout_thread.join if timeout_thread

        # A timeout was detected while waiting; the exception wins over any
        # exit-status error of the killed process
        raise timeout_exception if timed_out

        sout.join
        sout.close unless sout.closed?
        sout.annotate(out)

        out.exit_status = status.exitstatus
        if status && ! status.success? && ! no_fail
          if !err.empty?
            raise ProcessFailed.new pid, "#{cmd} failed with error status #{status.exitstatus}.\n#{err}"
          else
            raise ProcessFailed.new pid, "#{cmd} failed with error status #{status.exitstatus}"
          end
        else
          Log.log err, stderr if Integer === stderr and log
        end
        out.std_err = err if save_stderr
        out
      rescue Timeout
        # Abort the internal stream so pipes are closed, the input and error
        # threads are interrupted and the pid list is cleared
        sout.abort($!) unless sout.aborted?
        raise $!
      ensure
        post.call if post
      end
    end
  end

  def self.cmd_pid(*args)
    all_args = *args

    bar = all_args.last[:progress_bar] if Hash === all_args.last

    all_args << {} unless Hash === all_args.last

    level = all_args.last[:log] || 0
    level = 0 if TrueClass === level
    level = 10 if FalseClass === level
    level = level.to_i

    all_args.last[:log] = true
    all_args.last[:pipe] = true

    io = cmd(*all_args)
    pid = io.pids.first

    line = "" if bar
    starting = true
    while c = io.getc
      if starting
        if pid
          Log.logn "STDOUT [#{pid}]: ", level
        else
          Log.logn "STDOUT: ", level
        end
        starting = false
      end
      STDERR << c if Log.severity <= level
      line << c if bar
      if c == "\n"
        bar.process(line) if bar
        starting = true
        line = "" if bar
      end
    end
    begin
      io.join
      bar.remove if bar
    rescue
      bar.remove(true) if bar
      raise $!
    end

    nil
  end

  def self.cmd_log(*args)
    cmd_pid(*args)
    nil
  end

end
