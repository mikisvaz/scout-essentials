# Opt-in generic execution/availability primitives for test suites.
#
# Layering contract (see research/testing-availability-*.md in this repo):
# this module deliberately contains ONLY stdlib-generic primitives — PATH
# lookup, bounded child execution, and a bounded TCP connect. No interpreter,
# package, model, or network-service knowledge lives here: those probes
# belong to the layers that own them.
#
# This file is deliberately not required by scout-essentials.
require 'socket'

module Scout
  module Testing
    module Availability
      DEFAULT_TIMEOUT = 30
      TCP_TIMEOUT = 5
      OUTPUT_LIMIT = 65_536
      READ_CHUNK = 16 * 1024
      KILL_GRACE = 0.1
      CHUNK_POLL = 0.05
      TRUNCATION_NOTE = "\n[output truncated]"

      # Result of a run_command call: everything the caller needs to decide,
      # including the failure modes that are reported rather than raised.
      CommandResult = Struct.new(
        :argv, :success, :exit_status, :stdout, :stderr,
        :timed_out, :launch_error, keyword_init: true
      ) do
        def success?
          !!success
        end

        # Reason for a non-successful run, preferring the concrete failure
        # mode over raw output. Order: launch failure, timeout, exit status,
        # stderr, stdout.
        def reason
          return nil if success?
          return launch_error if launch_error
          return 'command timed out' if timed_out
          return "exit status #{exit_status}" if exit_status

          detail = stderr.to_s.strip
          return detail unless detail.empty?

          detail = stdout.to_s.strip
          return detail unless detail.empty?

          'could not start executable'
        end
      end

      class << self
        # True when name resolves to an executable on PATH, or contains a
        # path separator and names an executable file directly. No shell.
        def executable?(name)
          return false if name.to_s.empty?

          candidate = name.to_s
          if candidate.include?(File::SEPARATOR) || candidate.include?('\\')
            return File.file?(candidate) && File.executable?(candidate)
          end

          ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |directory|
            next false if directory.to_s.empty?

            path = File.join(directory, candidate)
            File.file?(path) && File.executable?(path)
          end
        end

        # Run argv (never a shell string) with a hard deadline. Both output
        # streams are drained concurrently so a chatty child cannot deadlock
        # a pipe, output is bounded per stream, and a timeout escalates
        # TERM -> KILL for the child process group.
        #
        # Launch failure (e.g. Errno::ENOENT) and timeout are reported on the
        # returned CommandResult, never raised. ArgumentError is raised only
        # for a non-positive/non-finite timeout or an empty argv, which are
        # programming errors. Not memoized: the answer can change per call.
        def run_command(argv, timeout: DEFAULT_TIMEOUT)
          argv = Array(argv).map(&:to_s)
          raise ArgumentError, 'argv must not be empty' if argv.empty?

          seconds = checked_timeout(timeout)

          out_read, out_write = IO.pipe
          err_read, err_write = IO.pipe
          pid = nil
          reaped = false
          killed = false
          readers = [out_read, err_read]
          stdout = +''
          stderr = +''
          status = nil

          begin
            pid = Process.spawn(*argv, out: out_write, err: err_write,
                                    pgroup: true, close_others: true)
          rescue StandardError => error
            close_all(readers + [out_write, err_write])
            return CommandResult.new(
              argv: argv, success: false, exit_status: nil,
              stdout: '', stderr: '', timed_out: false,
              launch_error: "#{error.class}: #{error.message}"
            )
          ensure
            # Closed in the parent regardless of spawn outcome, so EOF on the
            # read ends is meaningful.
            [out_write, err_write].each { |io| io.close unless io.closed? }
          end

          timed_out = false
          deadline = monotonic + seconds

          # Drain both pipes while waiting, so neither fills up and blocks
          # the child while this side is blocked on the other stream.
          until status && readers.empty?
            remaining = deadline - monotonic
            if remaining <= 0
              timed_out = true
              break
            end

            ready, = IO.select(readers, nil, nil, [remaining, CHUNK_POLL].min)
            Array(ready).each do |io|
              begin
                chunk = io.read_nonblock(READ_CHUNK)
                append_limited(io.equal?(out_read) ? stdout : stderr, chunk)
              rescue EOFError
                readers.delete(io)
                io.close
              end
            end

            next if status

            waited, candidate = Process.waitpid2(pid, Process::WNOHANG)
            if waited
              status = candidate
              reaped = true
            end
          end

          if timed_out
            killed = true
            status ||= terminate_group(pid)
            reaped = true
            stderr = note(stderr, "command timed out after #{seconds}s")
          end

          close_all(readers)

          CommandResult.new(
            argv: argv,
            success: !timed_out && status&.exitstatus == 0,
            exit_status: status&.exitstatus,
            stdout: stdout,
            stderr: stderr,
            timed_out: timed_out,
            launch_error: nil
          )
        ensure
          close_all(readers) if readers
          unless pid.nil? || reaped
            terminate_group(pid) unless killed
            reap(pid)
          end
        end

        # True means only that a TCP connection to host:port was established
        # within the timeout. A malformed port (non-numeric string, out of
        # range) reports false rather than raising; only an invalid timeout
        # raises, since that is a programming error. No memoization:
        # reachability can change.
        def tcp_reachable?(host, port, timeout: TCP_TIMEOUT)
          seconds = checked_timeout(timeout)
          port = Integer(port) rescue nil
          return false unless (1..65_535).cover?(port) && !host.to_s.empty?

          begin
            Socket.tcp(host.to_s, port, connect_timeout: seconds) do |socket|
              socket.close
            end
            true
          rescue SocketError, SystemCallError, IOError, ArgumentError
            false
          end
        end

        private

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def checked_timeout(value)
          number = Float(value)
          unless number.positive? && number.finite?
            raise ArgumentError, 'timeout must be positive and finite'
          end

          number
        end

        def close_all(ios)
          ios.each { |io| io.close unless io.closed? }
        rescue IOError
          nil
        end

        # TERM the process group, wait a short grace period, then KILL.
        # Returns the exit status when this call reaped the child, nil when
        # the child was already reaped elsewhere or had to be killed.
        def terminate_group(pid)
          signal_group(pid, 'TERM')
          grace = monotonic + KILL_GRACE
          loop do
            waited, status = waitpid_nohang(pid)
            return status if waited
            break if monotonic >= grace

            sleep(CHUNK_POLL / 2)
          end
          signal_group(pid, 'KILL')
          nil
        end

        def waitpid_nohang(pid)
          Process.waitpid2(pid, Process::WNOHANG)
        rescue Errno::ECHILD
          [false, nil]
        end

        def signal_group(pid, signal)
          Process.kill(signal, -pid)
        rescue SystemCallError
          begin
            Process.kill(signal, pid)
          rescue SystemCallError
            nil
          end
        end

        def reap(pid)
          waited, status = Process.waitpid2(pid)
          waited ? status : nil
        rescue Errno::ECHILD
          nil
        end

        def append_limited(buffer, chunk)
          remaining = OUTPUT_LIMIT - buffer.bytesize
          buffer << chunk.byteslice(0, remaining) if remaining.positive?
          marker = chunk.bytesize > remaining && !buffer.end_with?(TRUNCATION_NOTE)
          buffer << TRUNCATION_NOTE if marker
        end

        def note(text, addition)
          text.empty? ? addition : "#{text}\n#{addition}"
        end
      end
    end
  end
end
