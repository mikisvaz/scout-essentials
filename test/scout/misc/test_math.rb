require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscMath < Test::Unit::TestCase
  def test_mean
    assert_equal 4, Misc.mean([6,2])
  end
end

