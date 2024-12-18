require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMatches < Test::Unit::TestCase
  def test_match_value
    assert Misc.match_value('test', 'test')
  end
end

