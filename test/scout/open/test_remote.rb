require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/open'

class TestOpenRemote < Test::Unit::TestCase
  def test_wget
    teardown
    5.times do
      assert(Misc.fixutf8(Open.wget('http://google.com', :quiet => true, :nocache => true).read) =~ /html/)
      assert(Misc.fixutf8(Open.wget('http://google.com', :quiet => true).read) =~ /html/)
    end
  end

  def test_ssh
    TmpFile.with_file("TEST") do |f|
      begin
        assert_equal "TEST", Open.ssh("ssh://localhost:#{f}").read
      rescue ConcurrentStreamProcessFailed
        raise $! unless $!.message.include? "Connection refused"
      end
    end if false
  end
end

