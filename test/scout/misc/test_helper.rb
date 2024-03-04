require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscHelper < Test::Unit::TestCase
  def test_divide
    assert_equal 2, Misc.divide(%w(1 2 3 4 5 6 7 8 9),2).length
  end

  def test_ordered_divide
    assert_equal 5, Misc.ordered_divide(%w(1 2 3 4 5 6 7 8 9),2).length
  end

end

