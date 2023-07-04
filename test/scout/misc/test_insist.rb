require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscInsist < Test::Unit::TestCase
  def test_insist
    i = 0
    Misc.insist do 
      i += 1
      raise "Not yet" if i < 3
    end
  end
end

