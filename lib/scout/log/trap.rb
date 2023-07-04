module Log
  def self.trap_std(msg = "STDOUT", msge = "STDERR", severity = 0, severity_err = nil)
    sout, sin = Open.pipe
    soute, sine = Open.pipe
    backup_stderr = STDERR.dup
    backup_stdout = STDOUT.dup
    old_logfile = Log.logfile
    Log.logfile(backup_stderr)

    severity_err ||= severity
    th_log = Thread.new do
      while line = sout.gets
        Log.logn "#{msg}: " + line, severity
      end
    end

    th_loge = Thread.new do
      while line = soute.gets
        Log.logn "#{msge}: " + line, severity_err
      end
    end

    begin
      STDOUT.reopen(sin)
      STDERR.reopen(sine)
      yield
    ensure
      STDERR.reopen backup_stderr
      STDOUT.reopen backup_stdout
      sin.close
      sine.close
      th_log.join
      th_loge.join
      backup_stdout.close
      backup_stderr.close
      Log.logfile = old_logfile
    end
  end

  def self.trap_stderr(msg = "STDERR", severity = 0)
    sout, sin = Open.pipe
    backup_stderr = STDERR.dup
    old_logfile = Log.logfile
    Log.logfile(backup_stderr)

    th_log = Thread.new do
      while line = sout.gets
        Log.logn "#{msg}: " + line, severity
      end
    end

    begin
      STDERR.reopen(sin)
      yield
      sin.close
    ensure
      STDERR.reopen backup_stderr
      th_log.join
      backup_stderr.close
      Log.logfile = old_logfile
    end
  end

  def self._ignore_stderr
    begin
      File.open('/dev/null', 'w') do |f|
        backup_stderr = STDERR.dup
        STDERR.reopen(f)
        begin
          yield
        ensure
          STDERR.reopen backup_stderr
          backup_stderr.close
        end
      end
    rescue Errno::ENOENT
      yield
    end
  end


  def self.ignore_stderr(&block)
    _ignore_stderr &block
  end

  def self._ignore_stdout
    begin
      File.open('/dev/null', 'w') do |f|
        backup_stdout = STDOUT.dup
        STDOUT.reopen(f)
        begin
          yield
        ensure
          STDOUT.reopen backup_stdout
          backup_stdout.close
        end
      end
    rescue Errno::ENOENT
      yield
    end
  end


  def self.ignore_stdout(&block)
    _ignore_stdout &block
  end
end
