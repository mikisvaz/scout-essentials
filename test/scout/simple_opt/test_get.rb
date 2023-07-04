require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/simple_opt'
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSOPTParse < Test::Unit::TestCase
  def test_consume
    SOPT.parse("-f--first* first arg:-f--fun")
    args = "-f myfile --fun".split(" ")
    assert_equal "myfile", SOPT.consume(args)[:first]
  end
end
