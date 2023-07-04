require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPersist < Test::Unit::TestCase
  def test_string
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST"
      type = :string
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ raise "Error" }
    end
  end

  def test_float_array
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = [1.2,2.2]
      type = :float_array
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ raise "Error" }
    end
  end

  def test_string_update
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST"
      type = :string
      refute tmpdir.persist.glob("*").any?
      assert_equal obj, Persist.persist(tmpfile, type, :dir => tmpdir.persist){ obj }
      assert tmpdir.persist.glob("*").any?
      assert_raises ScoutException do 
        Persist.persist(tmpfile, type, :dir => tmpdir.persist, :update => true){ raise ScoutException }
      end
      assert_raises ScoutException do 
        Persist.persist(tmpfile, type, :persist_dir => tmpdir.persist, :persist_update => true){ raise ScoutException }
      end
    end
  end

  def test_stream
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST\nTEST"
      stream = StringIO.new obj
      stream.rewind
      res = Persist.persist(tmpfile, :string, :dir => tmpdir.persist){ stream }
      assert IO === res
      assert_equal obj, res.read
      assert_equal obj, Persist.persist(tmpfile, :string, :dir => tmpdir.persist){ raise ScoutException }
    end
  end

  def test_stream_multiple
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      obj = "TEST\nTEST"
      stream = StringIO.new obj
      stream.rewind
      res1 = Persist.persist(tmpfile, :string, :dir => tmpdir.persist, :tee_copies => 2){ stream }
      res2 = res1.next
      assert IO === res1
      assert_equal obj, res1.read
      assert_equal obj, res2.read
      assert_equal obj, Persist.persist(tmpfile, :string, :dir => tmpdir.persist){ raise ScoutException }
    end
  end

  def test_update_time
    TmpFile.with_file do |dir|
      Path.setup(dir)
      obj = "TEST"
      type = :string

      Open.write(dir.file, "TEST")
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file) }
      Open.rm(dir.file)
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file) }

      sleep 1
      Open.write(dir.file2, "TEST2")
      assert_equal "TEST", Persist.persist(dir.cache, type, :dir => tmpdir.persist){ Open.read(dir.file2) }
      assert_equal "TEST2", Persist.persist(dir.cache, type, :dir => tmpdir.persist, :update => dir.file2){ Open.read(dir.file2) }

      sleep 1
      Open.write(dir.file3, "TEST3")
      sleep 1
      Open.touch tmpdir.persist.glob("*").first
      assert_equal "TEST2", Persist.persist(dir.cache, type, :dir => tmpdir.persist, :update => dir.file3){ Open.read(dir.file3) }
    end
  end

  def test_concurrent
    num = 10

    s = 0.01
    10.times do
      TmpFile.with_file do |file|
        output1 = file + '.output1'
        output2 = file + '.output2'
        pid1 = Process.fork do
          Open.purge_pipes
          sleep rand/10.0
          io = Persist.persist("test", :string, :path => file) do
            Open.open_pipe do |sin|
              num.times do |i|
                sin.puts "line-#{i}-#{Process.pid}"
                sleep s
              end
            end
          end

          if IO === io
            Open.consume_stream(io, false)
          else
            Open.write(output1, io)
          end
        end
        pid2 = Process.fork do
          Open.purge_pipes
          sleep rand/10.0
          io = Persist.persist("test", :string, :path => file) do
            Open.open_pipe do |sin|
              num.times do |i|
                sin.puts "line-#{i}-#{Process.pid}"
                sleep s
              end
            end
          end
          if IO === io
            Open.consume_stream(io, false)
          else
            Open.write(output2, io)
          end
        end
        Process.waitpid pid1
        Process.waitpid pid2

        assert File.exist?(output1) || File.exist?(output2)
        [pid1, pid2].zip([output2, output1]).each do |pid, found|
          next unless File.exist?(found)
          assert Open.read(found).include? "-#{pid}\n"
        end
        [pid1, pid2].zip([output1, output2]).each do |pid, found|
          next unless File.exist?(found)
          refute Open.read(found).include? "-#{pid}\n"
        end
        Open.rm file
        Open.rm output1
        Open.rm output2
      end
    end
  end

  def test_path_prefix
    Persist.persist('foo', :tsv, :prefix => "TSV") do |filename|
      assert File.basename(filename).start_with? "TSV"
    end
  end

  def __test_speed
    times = 100_000
    TmpFile.with_file do |tmpfile|
      sout = Persist.persist(tmpfile, :string, :path => tmpfile) do
        Open.open_pipe do |sin|
          times.times do |i|
            sin.puts "line-#{i}"
          end
        end
      end

      Log::ProgressBar.with_bar do |bar|
        while l = sout.gets
          bar.tick
        end
      end
    end
  end

end

