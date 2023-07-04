require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/path'
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSOPTParse < Test::Unit::TestCase
  def test_parse
    SOPT.parse("-f--first* first arg:-f--fun")
    assert_equal "fun", SOPT.shortcuts["fu"]
  end
end
