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
end
