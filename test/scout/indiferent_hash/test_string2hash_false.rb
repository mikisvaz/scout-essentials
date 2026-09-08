require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/indiferent_hash'

class TestIndiferentString2HashFalse < Test::Unit::TestCase
  def test_true_becomes_trueclass
    assert_equal({ 'a' => true }, IndiferentHash.string2hash('a=true'))
  end

  def test_false_stays_the_string_false
    # asymmetry: 'true' converts, 'false' does not
    assert_equal({ 'a' => 'false' }, IndiferentHash.string2hash('a=false'))
  end
end
