require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/tmpfile'

class TestLock < Test::Unit::TestCase
  def test_locks
    num = 10
    TmpFile.with_file do |lockfile|
      TmpFile.with_file do |output|
        f = File.open(output, 'w') 
        thrs = num.times.collect do 
          Thread.new do
            Open.lock lockfile, true, min_sleep: 0.01, max_sleep: 0.05, sleep_inc: 0.001 do
              f.write "["
              sleep 0.01
              f.write "]"
            end
          end
        end
        thrs.each{|t| t.join }
        f.close
        assert_equal "[]" * num, File.open(output).read 
      end
    end
  end

  def test_keep_locked
    num = 10
    TmpFile.with_file do |lockfile|
      TmpFile.with_file do |output|
        f = File.open(output, 'w') 
        thrs = num.times.collect do 
          Thread.new do
            lock = Lockfile.new(lockfile, min_sleep: 0.01, max_sleep: 0.05, sleep_inc: 0.001)
            res = Open.lock lock do
              f.write "["
              raise KeepLocked, "1"
            end
            f.write res
            f.write "]"
            lock.unlock
          end
        end
        thrs.each{|t| t.join }
        f.close
        assert_equal "[1]" * num, File.open(output).read 
      end
    end
  end
end

