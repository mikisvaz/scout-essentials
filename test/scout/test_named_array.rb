require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestNamedArray < Test::Unit::TestCase
  def test_identify_names
    names =<<-EOF.split("\n")
ValueA
ValueB (Entity type)
15
    EOF
    assert_equal 0, NamedArray.identify_name(names, "ValueA")
    assert_equal :key, NamedArray.identify_name(names, :key)
    assert_equal 0, NamedArray.identify_name(names, nil)
    assert_equal 1, NamedArray.identify_name(names, "ValueB (Entity type)")
    assert_equal 1, NamedArray.identify_name(names, "ValueB")
    assert_equal 1, NamedArray.identify_name(names, 1)
  end

  def test_missing_field
    a = NamedArray.setup([1,2], [:a, :b])
    assert_equal 1, a[:a]
    assert_equal nil, a[:c]
  end

  def test_zip_fields
    a = [%w(a b), %w(1 1)]
    assert_equal [%w(a 1), %w(b 1)], NamedArray.zip_fields(a)
  end

  def test_add_zipped
    a = [%w(a b), %w(1 1)]
    NamedArray.add_zipped a, [%w(c), %w(1)]
    NamedArray.add_zipped a, [%w(d), %w(1)]
    assert_equal [%w(a b c d), %w(1 1 1 1)], a
  end

  def test_method_missing
    a = NamedArray.setup([1,2], [:a, :b])
    assert_equal 1, a.a
    assert_equal 2, a.b
  end

  def test_to_hash
    a = NamedArray.setup([1,2], [:a, :b])
    assert_equal 1, a.to_hash[:a]
    assert_equal 2, a.to_hash[:b]
  end
end
