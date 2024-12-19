require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestClass < Test::Unit::TestCase
  def test_indiferent_hash
    a = {:a => 1, "b" => 2}
    a.extend IndiferentHash

    assert_equal 1, a[:a]
    assert_equal 1, a["a"]
    assert_equal 2, a["b"]
    assert_equal 2, a[:b]
  end

  def test_case_insensitive_hash
    a = {:a => 1, "b" => 2}
    a.extend CaseInsensitiveHash

    assert_equal 1, a[:a]
    assert_equal 1, a["A"]
    assert_equal 1, a[:A]
    assert_equal 2, a["B"]
    assert_equal 2, a[:b]
  end

  def test_deep_merge
    o = {h: {a: 1, b: 2}}
    n = {h: {c: 3}}

    IndiferentHash.setup(o)
    o = o.deep_merge(n)

    assert_equal 1, o[:h]["a"]
    assert_equal 3, o[:h]["c"]
  end
end

