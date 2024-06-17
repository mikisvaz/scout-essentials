require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscMath < Test::Unit::TestCase
  def test_mean
    assert_equal 4, Misc.mean([6,2])
  end

  def test_softmax
    assert_equal 0.5, Misc.softmax([1,1]).first
    assert Misc.softmax([1,2]).first < 0.5
    assert Misc.softmax([2,1]).first > 0.5
  end
end

