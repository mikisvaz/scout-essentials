require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestFingerprint < Test::Unit::TestCase
  def test_str
    str = "Start-" + ("0123456789" * 20) + "-End"
    assert_equal 150, Log.fingerprint(str).length
  end
end

