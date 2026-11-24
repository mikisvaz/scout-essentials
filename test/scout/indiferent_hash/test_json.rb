require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestIndiferentHash < Test::Unit::TestCase
  def test_json
    h = IndiferentHash.setup({})
    h['a'] = 1
    h[:a] = 1

    assert_equal ['a'], JSON.parse(h.to_json).keys
  end
end

