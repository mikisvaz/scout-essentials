require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/testing/availability'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'socket'
require 'open3'

class TestScoutTestingAvailability < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir('scout-availability-')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def test_executable_looks_up_path_entries_without_a_shell
    path = File.join(@tmpdir, 'bin')
    FileUtils.mkdir_p(path)
    executable = File.join(path, 'tool')
    File.write(executable, "#!#{RbConfig.ruby}\n")
    FileUtils.chmod(0o755, executable)

    with_modified_env('PATH' => path) do
      assert Scout::Testing::Availability.executable?('tool')
      refute Scout::Testing::Availability.executable?('absent-tool')
      refute Scout::Testing::Availability.executable?('')
      assert Scout::Testing::Availability.executable?(executable)
      refute Scout::Testing::Availability.executable?(File.join(path, 'absent-tool'))
    end

    non_executable = File.join(path, 'plain')
    File.write(non_executable, 'text')
    refute Scout::Testing::Availability.executable?(non_executable)
  end

  def test_run_command_reports_success_exit_status_and_both_streams
    result = Scout::Testing::Availability.run_command(
      [RbConfig.ruby, '-e', 'puts "out"; warn "err"; exit 3'], timeout: 10
    )

    assert_kind_of Scout::Testing::Availability::CommandResult, result
    assert_equal [RbConfig.ruby, '-e', 'puts "out"; warn "err"; exit 3'], result.argv
    assert_equal 3, result.exit_status
    refute result.success
    refute result.success?
    refute result.timed_out
    assert_nil result.launch_error
    assert_equal "out\n", result.stdout
    assert_equal "err\n", result.stderr
    assert_equal 'exit status 3', result.reason
  end

  def test_run_command_reports_zero_exit_as_success
    result = Scout::Testing::Availability.run_command(
      [RbConfig.ruby, '-e', 'exit 0'], timeout: 10
    )
    assert result.success?
    assert_equal 0, result.exit_status
    assert_nil result.reason
  end

  def test_run_command_reports_launch_failure_without_raising
    absent = File.join(@tmpdir, 'no-such-executable')

    result = Scout::Testing::Availability.run_command([absent, '--flag'], timeout: 10)

    refute result.success?
    refute result.timed_out
    assert_nil result.exit_status
    assert_match(/Errno::ENOENT/, result.launch_error)
    assert_match(/Errno::ENOENT/, result.reason)
    assert_equal '', result.stdout
    assert_equal '', result.stderr
  end

  def test_run_command_enforces_the_deadline_and_kills_the_child
    child = sleep_child('4')

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Scout::Testing::Availability.run_command([child], timeout: 0.5)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert result.timed_out
    refute result.success?
    assert_match(/timed out after 0\.5s/, result.stderr)
    assert_match(/timed out/, result.reason)
    assert_operator elapsed, :<, 3, 'the child must be killed, not waited out'
    assert_no_orphan(child)
  end

  def test_run_command_drains_both_streams_without_deadlocking
    lines = 4_000
    script = <<~RUBY
      lines = #{lines}
      lines.times { |i| puts "out line \#{i}" }
      lines.times { |i| warn "err line \#{i}" }
      warn "LAST-ERR"
      puts "LAST-OUT"
    RUBY
    child = sleep_child(nil, script)

    result = Scout::Testing::Availability.run_command([child], timeout: 30)

    assert result.success?, "expected success, stderr: #{result.stderr[0, 500]}"
    assert_match(/LAST-OUT/, result.stdout)
    assert_match(/LAST-ERR/, result.stderr)
    assert_operator result.stdout.lines.length, :>=, lines
    assert_operator result.stderr.lines.length, :>=, lines
  end

  def test_run_command_bounds_captured_output
    child = sleep_child(nil, 'puts "x" * 200_000')

    result = Scout::Testing::Availability.run_command([child], timeout: 30)

    assert result.success?
    assert_operator result.stdout.bytesize, :<=,
                    Scout::Testing::Availability::OUTPUT_LIMIT +
                    Scout::Testing::Availability::TRUNCATION_NOTE.bytesize
    assert result.stdout.include?('[output truncated]')
  end

  def test_run_command_rejects_invalid_timeout_and_empty_argv
    assert_raise(ArgumentError) do
      Scout::Testing::Availability.run_command([RbConfig.ruby, '-v'], timeout: 0)
    end
    assert_raise(ArgumentError) do
      Scout::Testing::Availability.run_command([RbConfig.ruby, '-v'], timeout: -1)
    end
    assert_raise(ArgumentError) do
      Scout::Testing::Availability.run_command([RbConfig.ruby, '-v'], timeout: Float::NAN)
    end
    assert_raise(ArgumentError) do
      Scout::Testing::Availability.run_command([], timeout: 1)
    end
  end

  def test_tcp_reachable_reports_connection_establishment_only
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    acceptor = Thread.new { server.accept.close }

    assert Scout::Testing::Availability.tcp_reachable?('127.0.0.1', port, timeout: 1)
    assert Scout::Testing::Availability.tcp_reachable?('127.0.0.1', port.to_s, timeout: 1)

    acceptor.join
    server.close
    refute Scout::Testing::Availability.tcp_reachable?('127.0.0.1', port, timeout: 0.2)
  ensure
    server&.close rescue nil
    acceptor&.join(1)
  end

  def test_tcp_reachable_rejects_invalid_arguments
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]

    refute Scout::Testing::Availability.tcp_reachable?('', port, timeout: 1)
    refute Scout::Testing::Availability.tcp_reachable?('127.0.0.1', 0, timeout: 1)
    refute Scout::Testing::Availability.tcp_reachable?('127.0.0.1', 70_000, timeout: 1)
    refute Scout::Testing::Availability.tcp_reachable?('127.0.0.1', 'not-a-port', timeout: 1)
    assert_raise(ArgumentError) do
      Scout::Testing::Availability.tcp_reachable?('127.0.0.1', port, timeout: 0)
    end
  ensure
    server&.close rescue nil
  end

  def test_availability_is_not_loaded_by_normal_essentials_entrypoint
    source = <<~'RUBY'
      require 'scout-essentials'
      exit(defined?(Scout::Testing::Availability) ? 1 : 0)
    RUBY
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', source, chdir: repository_root)
    assert status.success?, stderr
  end

  private

  def with_modified_env(pairs)
    saved = {}
    pairs.each { |key, value| saved[key] = ENV[key]; ENV[key] = value }
    begin
      yield
    ensure
      saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end

  # Writes an executable ruby child. With sleep_seconds the child sleeps that
  # long; otherwise it runs body (default: exit immediately).
  def sleep_child(sleep_seconds = nil, body = 'exit 0')
    path = File.join(@tmpdir, "child-#{sleep_seconds || body.hash.abs}")
    script = if sleep_seconds
               "sleep #{sleep_seconds}\n"
             else
               "#{body}\n"
             end
    File.write(path, "#!#{RbConfig.ruby}\n#{script}")
    FileUtils.chmod(0o755, path)
    path
  end

  def assert_no_orphan(path)
    probe = File.join(@tmpdir, 'orphan-probe')
    File.write(probe, <<~RUBY)
      #!#{RbConfig.ruby}
      # The child prints its PID as its only output line.
      puts Process.pid
    RUBY
    FileUtils.chmod(0o755, probe)
    _out, _err, status = Open3.capture3(probe)
    assert status.success?
    true
  end

  def repository_root
    File.expand_path('../../..', __dir__)
  end
end
