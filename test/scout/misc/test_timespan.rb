require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/misc/format'

class TestMiscTimespan < Test::Unit::TestCase
  def test_plain_units
    assert_equal 5, Misc.timespan('5s')
    assert_equal 60, Misc.timespan('1m')
    assert_equal 3600, Misc.timespan('1h')
    assert_equal 86400, Misc.timespan('1d')
  end

  def test_negative
    assert_equal(-5, Misc.timespan('-5s'))
  end

  def test_space_separated_units_add_up
    assert_equal 90, Misc.timespan('1m 30s')
    assert_equal 5400, Misc.timespan('1h 30m')
  end

  def test_glued_units_raise
    # The scan is /(\d+)(\w*)/ and greedy: '1m30s' pairs 1 with the
    # unknown token 'm30s', so the multiplication sees nil and raises.
    assert_raise(TypeError) { Misc.timespan('1m30s') }
  end

  def test_unknown_unit_raises
    assert_raise(TypeError) { Misc.timespan('1x') }
  end
end
