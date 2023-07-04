require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestOptions < Test::Unit::TestCase


  def test_add_defaults
    options = {:a => 1, "b" => 2}
    assert_equal 2, IndiferentHash.add_defaults(options, :b => 3)["b"]
    assert_equal 2, IndiferentHash.add_defaults(options, "b" => 3)["b"]
    assert_equal 3, IndiferentHash.add_defaults(options, :c => 3)["c"]
    assert_equal 3, IndiferentHash.add_defaults(options, "c" => 4)[:c]
    assert_equal 3, IndiferentHash.add_defaults(options, "c" => 4)["c"]
  end

  def test_positions2hash
    inputs = IndiferentHash.positional2hash([:one, :two, :three], 1, :two => 2, :four => 4)
    assert_equal 1, inputs[:one]
    assert_equal 2, inputs[:two]
    assert_equal nil, inputs[:three]
    assert_equal nil, inputs[:four]
  end

  def test_process_to_hash
    list = [1,2,3,4]
    assert_equal 4, IndiferentHash.process_to_hash(list){|l| l.collect{|e| e * 2 } }[2]
  end

  def test_hash2string
    hash = {}
    assert_equal hash, IndiferentHash.string2hash(IndiferentHash.hash2string(hash))

    hash = {:a => 1}
    assert_equal hash, IndiferentHash.string2hash(IndiferentHash.hash2string(hash))

    hash = {:a => true}
    assert_equal hash, IndiferentHash.string2hash(IndiferentHash.hash2string(hash))

    hash = {:a => :b}
    assert_equal hash, IndiferentHash.string2hash(IndiferentHash.hash2string(hash))

    hash = {:a => /test/}
    assert_equal({}, IndiferentHash.string2hash(IndiferentHash.hash2string(hash)))
  end
end

