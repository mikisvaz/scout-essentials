require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/exceptions'
require 'scout/cmd'

class TestClass < Test::Unit::TestCase
  def test_concurrent_stream_pipe
    io = CMD.cmd("ls", :pipe => true, :autojoin => true)
    io.read
    io.close 
  end

  def test_concurrent_stream_process_failed
    assert_raise ConcurrentStreamProcessFailed do 
      io = CMD.cmd("grep . NONEXISTINGFILE", :pipe => true, :autojoin => true)
      io.read
      io.close 
    end
  end

  def test_concurrent_stream_process_failed_autojoin
    assert_raise ConcurrentStreamProcessFailed do 
      io = CMD.cmd("grep . NONEXISTINGFILE", :pipe => true, :autojoin => true) 
      io.read
    end
  end
end

