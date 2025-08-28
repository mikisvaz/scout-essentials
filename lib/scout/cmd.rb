require_relative 'indiferent_hash'
require_relative 'concurrent_stream'
require_relative 'log'
require_relative 'open/stream'
require 'stringio'
require 'open3'

module CMD

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
          CMD.cmd("#{cmd} --help")
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

  def self.cmd(tool, cmd = nil, options = {}, &block)
    options, cmd = cmd, nil if Hash === cmd

    options    = IndiferentHash.add_defaults options, :stderr => Log::DEBUG
    in_content = options.delete(:in)
    stderr     = options.delete(:stderr)
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

    dont_close_in  = options.delete(:dont_close_in)

    log = true if log.nil?

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

    in_content = StringIO.new in_content if String === in_content

    sin, sout, serr, wait_thr = begin
                                  Open3.popen3(ENV, cmd)
                                rescue
                                  Log.warn $!.message
                                  raise ProcessFailed, nil, cmd unless no_fail
                                  return
                                end
    pid = wait_thr.pid

    Log.debug{"CMD: [#{pid}] #{cmd}".strip if log}

    if in_content.respond_to?(:read)
      in_thread = Thread.new(Thread.current) do |parent|
        begin
          Thread.current.report_on_exception = false if no_fail
          Thread.current["name"] = "CMD in"
          while c = in_content.read(Open::BLOCK_SIZE)
            sin << c
          end
          sin.close  unless sin.closed?

          unless dont_close_in
            in_content.close unless in_content.closed?
            in_content.join if in_content.respond_to? :join
          end
        rescue
          Log.error "Error in CMD  [#{pid}] #{cmd}: #{$!.message}" unless no_fail
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
          begin
          while line = serr.gets
            bar.process(line) if bar
            sout.log = line
            sout.std_err << line if save_stderr
            Log.log "STDERR [#{pid}]: " +  line, stderr if log
          end
          serr.close
          rescue
            Log.exception $!
            raise $!
          end
        end
      else
        err_thread = Open.consume_stream(serr, true)
      end

      sout.threads = [in_thread, err_thread, wait_thr].compact

      sout
    else

      if bar
        err = ""
        err_thread = Thread.new do
          while not serr.eof?
            line = serr.gets
            bar.process(line)
            err << line if Integer === stderr and log
          end
          serr.close
        end
      elsif log and Integer === stderr
        err = ""
        err_thread = Thread.new do
          while not serr.eof?
            err += serr.gets
          end
          serr.close
        end
      else
        Open.consume_stream(serr, true)
        err_thread = nil
        err = ""
      end

      ConcurrentStream.setup sout, :pids => pids, :threads => [in_thread, err_thread].compact, :autojoin => autojoin, :no_fail => no_fail

      begin
        out = StringIO.new sout.read
        sout.close unless sout.closed?

        status = wait_thr.value
        if status && ! status.success? && ! no_fail
          if !err.empty?
            raise ProcessFailed.new pid, "#{cmd} failed with error status #{status.exitstatus}.\n#{err}"
          else
            raise ProcessFailed.new pid, "#{cmd} failed with error status #{status.exitstatus}"
          end
        else
          Log.log err, stderr if Integer === stderr and log
        end
        out
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
