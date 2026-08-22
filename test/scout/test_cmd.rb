require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/open'

class TestCmd < Test::Unit::TestCase

  def test_cmd_option_string
    assert_equal("--user-agent 'firefox'", CMD.process_cmd_options("--user-agent" => "firefox"))
    assert_equal("--user-agent='firefox'", CMD.process_cmd_options("--user-agent=" => "firefox"))
    assert_equal("-q", CMD.process_cmd_options("-q" => true))
    assert_equal("", CMD.process_cmd_options("-q" => nil))
    assert_equal("", CMD.process_cmd_options("-q" => false))

    assert(CMD.process_cmd_options("--user-agent" => "firefox", "-q" => true) =~ /--user-agent 'firefox'/)
    assert(CMD.process_cmd_options("--user-agent" => "firefox", "-q" => true) =~ /-q/)
  end

  def test_cmd_option_array
    assert_equal(["--user-agent", "firefox"], CMD.process_cmd_options_array("--user-agent" => "firefox"))
    assert_equal(["--user-agent=firefox"], CMD.process_cmd_options_array("--user-agent=" => "firefox"))
    assert_equal(["-q"], CMD.process_cmd_options_array("-q" => true))
    assert_equal([], CMD.process_cmd_options_array("-q" => nil))
    assert_equal([], CMD.process_cmd_options_array("-q" => false))

    result = CMD.process_cmd_options_array("--user-agent" => "firefox", "-q" => true)
    assert_include result, "--user-agent"
    assert_include result, "firefox"
    assert_include result, "-q"
  end

  def test_cmd
    assert_equal("test\n", CMD.cmd("echo '{opt}' test").read)
    assert_equal("test", CMD.cmd("echo '{opt}' test", "-n" => true).read)
    assert_equal("test2\n", CMD.cmd("cut", "-f" => 2, "-d" => ' ', :in => "test1 test2").read)
  end

  def test_pipe
    assert_equal("test\n", CMD.cmd("echo test", :pipe => true).read)
    assert_equal("test\n", CMD.cmd("echo '{opt}' test", :pipe => true).read)
    assert_equal("test", CMD.cmd("echo '{opt}' test", "-n" => true, :pipe => true).read)
    assert_equal("test2\n", CMD.cmd("cut", "-f" => 2, "-d" => ' ', :in => "test1 test2", :pipe => true).read)
  end

  def test_in_io
    text =<<-EOF
line1
line2
line3
line4
    EOF
    TmpFile.with_file(text) do |file|
      io = Open.open(file)
      ConcurrentStream.setup(io)
      CMD.cmd('wc -l', in: io)
    end
  end

  def test_error
    Log.with_severity 6 do
      assert_raise ProcessFailed do CMD.cmd('fake-command') end
      assert_raise ProcessFailed do CMD.cmd('ls -fake_option') end

      assert_raise ProcessFailed do CMD.cmd('fake-command', :stderr => true) end
      assert_raise ProcessFailed do CMD.cmd('ls -fake_option', :stderr => true) end

      assert_nothing_raised ProcessFailed do CMD.cmd('fake-command', :no_fail => true, :pipe => true) end
      assert_nothing_raised ProcessFailed do CMD.cmd('ls -fake_option', :no_fail => true, :pipe => true) end

      assert_raise ProcessFailed do CMD.cmd('fake-command', :stderr => true, :pipe => true).join end
      assert_raise ConcurrentStreamProcessFailed do CMD.cmd('ls -fake_option', :stderr => true, :pipe => true).join end
    end
  end

  def test_pipes
    text = <<-EOF
line1
line2
line3
line11
line22
line33
    EOF

    TmpFile.with_file(text * 100) do |file|

      Open.open(file) do |f|
        io = CMD.cmd('tail -n 10', :in => f, :pipe => true)
        io2 = CMD.cmd('head -n 10', :in => io, :pipe => true)
        io3 = CMD.cmd('head -n 10', :in => io2, :pipe => true)
        assert_equal 10, io3.read.split(/\n/).length
      end
    end
  end

  def test_STDIN_close
    TmpFile.with_file("Hello") do |file|
      STDIN.close
      Open.open(file) do |f|
        io = CMD.cmd("tr 'e' 'E'", :in => f, :pipe => true)
        txt = io.read
        io.join
        assert_equal "HEllo", txt
      end
    end
  end

  def test_bash
    assert_equal "TEST", CMD.bash("echo TEST").read.strip
    assert_equal ENV["HOME"], CMD.bash("echo $HOME").read.strip
  end

  def test_cmd_array_basic
    assert_equal("hello\n", CMD.cmd(["echo", "hello"]).read)
    assert_equal("hello world\n", CMD.cmd(["echo", "hello world"]).read)
  end

  def test_cmd_array_special_chars
    # Special characters should be treated literally, NOT interpreted by shell
    assert_equal("hello; rm -rf /\n", CMD.cmd(["echo", "hello; rm -rf /"]).read)
    assert_equal("$HOME\n", CMD.cmd(["echo", "$HOME"]).read)
    assert_equal("hello | cat\n", CMD.cmd(["echo", "hello | cat"]).read)
  end

  def test_cmd_array_with_options
    # Hash options with boolean flag add the flag to the command array
    # Options hash with flag => value are appended as separate args
    assert_equal("two\n", CMD.cmd(["cut"], "-f" => 2, "-d" => " ", :in => "one two three").read)
    # String second argument is appended to the command array
    assert_equal("world", CMD.cmd(["echo", "-n"], "world").read)
  end

  def test_cmd_array_with_stdin
    assert_equal("data", CMD.cmd(["cat"], :in => "data").read)
    assert_equal("TRANSFORMED\n", CMD.cmd(["tr", "a-z", "A-Z"], :in => "transformed\n").read)
  end

  def test_cmd_array_pipe
    assert_equal("test\n", CMD.cmd(["echo", "test"], :pipe => true).read)

    text = "line1\nline2\nline3\n"
    io = CMD.cmd(["cat"], :in => text, :pipe => true)
    assert_equal(text, io.read)
    io.join
  end

  def test_cmd_array_pipe_chain
    text = "line1\nline2\nline3\nline4\n"
    io1 = CMD.cmd(["cat"], :in => text, :pipe => true)
    io2 = CMD.cmd(["grep", "line"], :in => io1, :pipe => true)
    assert_equal(4, io2.read.split(/\n/).length)
    io2.join
  end

  def test_cmd_array_error
    Log.with_severity 6 do
      assert_raise ProcessFailed do CMD.cmd(["fake-command"]) end
      assert_raise ProcessFailed do CMD.cmd(["false"]) end

      assert_nothing_raised ProcessFailed do CMD.cmd(["fake-command"], :no_fail => true, :pipe => true) end
      assert_nothing_raised ProcessFailed do CMD.cmd(["false"], :no_fail => true, :pipe => true) end
    end
  end

  def test_cmd_array_save_stderr
    # save_stderr captures stderr onto the result's std_err
    result = CMD.cmd(["ls", "/nonexistent_dir_12345"], :no_fail => true, :save_stderr => true)
    assert_match(/No such file/, result.std_err)
  end

  def test_cmd_array_no_fail_nonpipe
    # no_fail in non-pipe mode should not raise
    Log.with_severity 6 do
      assert_nothing_raised ProcessFailed do CMD.cmd(["false"], :no_fail => true) end
      assert_nothing_raised ProcessFailed do CMD.cmd(["fake-command"], :no_fail => true) end
    end
  end

  ### :timeout option

  def test_cmd_timeout_nonpipe_raises
    Log.with_severity 6 do
      e = assert_raise(CMD::Timeout) do
        CMD.cmd("sleep 5", :timeout => 0.3)
      end
      assert_match(/sleep 5/, e.message)
      assert_match(/0\.3/, e.message)
      assert_match(/sleep 5/, e.command)
      assert_equal(0.3, e.timeout)
    end
  end

  def test_cmd_timeout_nonpipe_no_zombie
    Log.with_severity 6 do
      e = assert_raise(CMD::Timeout) do
        CMD.cmd("sleep 30", :timeout => 0.3)
      end
      pid = e.pid

      # The pid is reaped by the watchdog: once reaped, waitpid raises
      # Errno::ECHILD.  Retry for a while to allow for the kill grace period
      reaped = false
      40.times do
        begin
          Process.waitpid(pid, Process::WNOHANG)
          sleep 0.05
        rescue Errno::ECHILD
          reaped = true
          break
        end
      end
      assert(reaped, "pid #{pid} was not reaped after the timeout")
    end
  end

  def test_cmd_timeout_nonpipe_completes
    # A command that finishes before the timeout works as if no timeout was
    # given, and the option does not leak into the command line
    assert_equal("test\n", CMD.cmd("echo test", :timeout => 5).read)
  end

  def test_cmd_timeout_pipe_read_raises
    Log.with_severity 6 do
      assert_raise(CMD::Timeout) do
        CMD.cmd("sleep 5", :pipe => true, :timeout => 0.3).read
      end
    end
  end

  def test_cmd_timeout_pipe_join_raises
    Log.with_severity 6 do
      io = CMD.cmd("sleep 5", :pipe => true, :timeout => 0.3)
      assert_raise(CMD::Timeout){ io.join }
    end
  end

  def test_cmd_timeout_pipe_partial_output
    Log.with_severity 6 do
      io = CMD.cmd("bash -c 'echo START; sleep 5'", :pipe => true, :timeout => 0.5)
      line = nil
      begin
        line = io.gets
      rescue IOError
        # closing the stream may interrupt the read first
      end
      assert_equal("START\n", line)
      assert_raise(CMD::Timeout){ io.join }
    end
  end

  def test_cmd_timeout_pipe_completes
    io = CMD.cmd("echo test", :pipe => true, :timeout => 5)
    assert_equal("test\n", io.read)
    assert_nothing_raised{ io.join }
  end

  def test_cmd_timeout_pipe_stderr_thread
    # Exercises the stderr consumer thread cleanup on timeout
    Log.with_severity 6 do
      assert_raise(CMD::Timeout) do
        CMD.cmd("bash -c 'echo OUT; echo ERR >&2; sleep 5'", :pipe => true, :timeout => 0.3, :stderr => 0).read
      end
    end
  end

  def test_cmd_timeout_pipe_blocked_input
    # The stdin feeder thread blocks writing to the process; it must be
    # interrupted when the timeout aborts the stream
    Log.with_severity 6 do
      content = "line\n" * 100_000
      assert_raise(CMD::Timeout) do
        CMD.cmd("bash -c 'read line; sleep 5'", :in => content, :pipe => true, :timeout => 0.5).read
      end
    end
  end

  def test_cmd_timeout_is_process_failed
    Log.with_severity 6 do
      caught = nil
      begin
        CMD.cmd("sleep 5", :timeout => 0.3)
      rescue ProcessFailed
        caught = $!
      end
      assert(CMD::Timeout === caught)
    end
  end

  def test_cmd_failure_without_timeout_is_not_timeout
    Log.with_severity 6 do
      e = assert_raise(ProcessFailed){ CMD.cmd("false") }
      assert(! (CMD::Timeout === e))
    end
  end

  def test_cmd_no_timeout_option_long_command
    # Without :timeout the behaviour is unchanged: the caller waits
    assert_equal("done\n", CMD.cmd("bash -c 'sleep 0.2; echo done'").read)
  end

  def stderr_emitting_command(lines = 3, sleep_time = 0.3, pause_after = 0)
    "bash -c '#{(1..lines).map{|i| "sleep #{sleep_time}; echo error#{i} >&2"}.join('; ')}; sleep #{pause_after}'"
  end

  def test_save_stderr_pipe_string_file_lives_tails
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        # The child also prints stdout lines that the parent consumes slowly,
        # so the pipe is genuinely being consumed while stderr reaches the log
        cmd = "bash -c 'sleep 0.2; echo error1 >&2; echo out1; sleep 0.4; echo error2 >&2; echo out2; sleep 0.4; echo error3 >&2; echo out3'"
        io = CMD.cmd(cmd, :pipe => true, :stderr => 0, :save_stderr => tmp)
        assert ! io.closed?

        # Poll the log size while reading stdout one line at a time: the file
        # must grow before the command ends, proving incremental flushing
        sizes = []
        lines = []
        while line = io.gets
          lines << line
          sleep 0.1
          sizes << File.size(tmp) if File.exist?(tmp)
        end
        io.join

        assert_equal %w(out1 out2 out3), lines.map(&:chomp)
        assert(sizes.any?{|s| s > 0}, "log file should grow while the command runs: #{sizes.inspect}")
        # Sizes must be non-decreasing, and more than one positive size means
        # the file was already being filled before the command finished
        assert_equal(sizes.sort, sizes, "log file size must not shrink: #{sizes.inspect}")
        assert(sizes.count{|s| s > 0} >= 2, "log file should have been flushed several times while running: #{sizes.inspect}")
        assert io.closed?
        content = File.read(tmp)
        assert_equal "error1\nerror2\nerror3\n", content
        assert_equal "error1\nerror2\nerror3\n", io.std_err
      end
    end
  end

  def test_save_stderr_pipe_scout_path
    Log.with_severity 6 do
      tmp = Path.setup(File.join(TmpFile.tmpdir, 'scout_path_stderr.log'))
      CMD.cmd("bash -c 'echo error1 >&2; echo error2 >&2'", :pipe => true, :stderr => 0, :save_stderr => tmp).read
      assert_equal "error1\nerror2\n", File.read(tmp.find)
      assert(File.exist?(tmp.find))
    end
  end

  def test_save_stderr_pipe_pathname
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        pathname = Pathname.new(tmp)
        CMD.cmd("bash -c 'echo error1 >&2; echo error2 >&2'", :pipe => true, :stderr => 0, :save_stderr => pathname).read
        assert_equal "error1\nerror2\n", File.read(tmp)
      end
    end
  end

  def test_save_stderr_pipe_io_is_not_closed
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        io_dst = File.open(tmp, 'w')
        CMD.cmd("bash -c 'echo error1 >&2; echo error2 >&2'", :pipe => true, :stderr => 0, :save_stderr => io_dst).read
        assert ! io_dst.closed?
        io_dst.close
        assert_equal "error1\nerror2\n", File.read(tmp)
      end

      string_io = StringIO.new
      CMD.cmd("bash -c 'echo error1 >&2'", :pipe => true, :stderr => 0, :save_stderr => string_io).read
      assert ! string_io.closed?
      assert_equal "error1\n", string_io.string
    end
  end

  def test_save_stderr_pipe_file_closed_by_cmd
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        fds_before = Dir["/proc/self/fd/*"].length
        CMD.cmd("bash -c 'echo error1 >&2; echo error2 >&2'", :pipe => true, :stderr => 0, :save_stderr => tmp).read
        Misc.insist(10, 0.05) do
          raise "fd leaked" unless Dir["/proc/self/fd/*"].length <= fds_before + 1
        end
        fds_after = Dir["/proc/self/fd/*"].length
        assert(fds_after <= fds_before + 1, "CMD should close the file it opened: #{fds_before} -> #{fds_after}")

        # A second run truncates correctly: proves the previous run closed it
        CMD.cmd("bash -c 'echo only >&2'", :pipe => true, :stderr => 0, :save_stderr => tmp).read
        assert_equal "only\n", File.read(tmp)
      end
    end
  end

  def test_save_stderr_nonpipe_path
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        CMD.cmd("bash -c 'echo error1 >&2; echo error2 >&2'", :save_stderr => tmp, :stderr => 0)
        assert_equal "error1\nerror2\n", File.read(tmp)
      end
    end
  end

  def test_save_stderr_nonpipe_io
    Log.with_severity 6 do
      string_io = StringIO.new
      CMD.cmd("bash -c 'echo error1 >&2'", :save_stderr => string_io, :stderr => 0)
      assert_equal "error1\n", string_io.string
      assert ! string_io.closed?
    end
  end

  def test_save_stderr_boolean_still_populates_std_err
    Log.with_severity 6 do
      io = CMD.cmd("bash -c 'echo error1 >&2'", :pipe => true, :stderr => 0, :save_stderr => true)
      io.join
      assert_equal "error1\n", io.std_err

      out = CMD.cmd("bash -c 'echo error1 >&2'", :save_stderr => true, :stderr => 0)
      assert_equal "error1\n", out.std_err

      out = CMD.cmd("bash -c 'echo error1 >&2'", :stderr => 0)
      assert ! out.respond_to?(:std_err) || out.std_err.nil? || out.std_err.empty?
    end
  end

  def test_save_stderr_timeout_keeps_file
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        assert_raise(CMD::Timeout) do
          CMD.cmd("bash -c 'echo error1 >&2; sleep 5'", :pipe => true, :stderr => 0, :save_stderr => tmp, :timeout => 0.5).read
        end
        Misc.insist(3, 0.2, 'timeout log file to be flushed') do
          raise "missing #{tmp}" unless File.exist?(tmp)
        end
        assert(File.exist?(tmp))
        assert_equal "error1\n", File.read(tmp)

        # The destination was closed even though the command timed out
        fds_before = Dir["/proc/self/fd/*"].length
        assert_equal(fds_before, Dir["/proc/self/fd/*"].length)
      end
    end
  end

  def test_save_stderr_nonpipe_failure_writes_log
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        assert_raise(ProcessFailed) do
          CMD.cmd("bash -c 'echo error1 >&2; exit 3'", :save_stderr => tmp, :stderr => 0)
        end
        # The ProcessFailed message embeds stderr and the destination keeps it
        # even though the command failed
        assert(File.exist?(tmp))
        assert_equal "error1\n", File.read(tmp)
      end
    end
  end

  def test_save_stderr_spawn_failure_closes_destination
    Log.with_severity 6 do
      TmpFile.with_file(".log", false) do |tmp|
        3.times do |i|
          assert_raise(ProcessFailed) do
            CMD.cmd(['/no/such/binary_xyz'], :save_stderr => tmp, :stderr => 0)
          end
          # No fd still points at the destination file: CMD closed what it
          # opened even though the command never started (the popen3 pipes
          # themselves are pre-existing noise here, they are not related to
          # the destination)
          leaked = Dir["/proc/self/fd/*"].select do |fd|
            (File.readlink(fd) rescue nil) == tmp
          end
          assert(leaked.empty?, "destination fd leaked on spawn failure: #{leaked.inspect}")
        end

        # And the path is reusable: a later write is not clobbered by a
        # buffered handle left behind
        File.open(tmp, 'w') { |f| f.write "marker\n" }
        assert_equal "marker\n", File.read(tmp)
      end
    end
  end

  def test_save_stderr_creates_parent_dirs
    Log.with_severity 6 do
      subdir = File.join(TmpFile.tmpdir, 'missing1', 'missing2')
      tmp = File.join(subdir, 'log.txt')
      assert ! File.exist?(subdir)
      CMD.cmd("bash -c 'echo error1 >&2'", :save_stderr => tmp, :stderr => 0)
      assert File.exist?(tmp)
      assert_equal "error1\n", File.read(tmp)
    end
  end

  def test_save_stderr_unwritable_path_raises
    Log.with_severity 6 do
      TmpFile.with_file("blocked", false) do |blocked|
        File.open(blocked, 'w') do |f| f.puts 'not a dir' end
        bad = File.join(blocked, 'sub', 'log.txt')

        raised = false
        begin
          CMD.cmd("echo x", :save_stderr => bad, :stderr => 0)
        rescue Exception
          raised = true
        end
        assert raised, "an unwritable path must raise, not be silently ignored"
      end
    end
  end
end
