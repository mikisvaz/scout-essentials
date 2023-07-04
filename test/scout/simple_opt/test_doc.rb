require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestSimpleOptDoc < Test::Unit::TestCase
  def test_input_format
    assert_match 'default: :def', SOPT.input_format(:name, :type, :def, :n)
  end
  def test_input_doc
    inputs =<<-EOF.split("\n").collect{|l| l.split(" ") }
input1 integer Integer_input 10 i1
input2 float Float_input 0.2 i2
    EOF
    assert SOPT.input_array_doc(inputs).include?('-i1,--input1')
  end
end

