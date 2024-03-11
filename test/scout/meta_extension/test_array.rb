require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestExtensionArray < Test::Unit::TestCase
  module ExtensionClass
    extend MetaExtension

    extension_attr :code, :code2
  end

  module ExtensionClass2
    extend MetaExtension

    extension_attr :code3, :code4
  end

  def test_array
    ary = ["string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray
    assert_equal [ExtensionClass], ary.extension_types
    assert_equal code, ary.code
    assert_equal code, ary[0].code

    assert_equal code, ary.first.code
    assert_equal code, ary.last.code
  end

  def test_array_first_last
    %w(first last).each do |method|
      ary = ["string"]
      code = "Annotation String"
      ExtensionClass.setup(ary, code)
      ary.extend ExtendedArray
      assert_equal [ExtensionClass], ary.extension_types

      assert_equal code, ary.send(method).code
    end
  end

  def test_array_each
    ary = ["string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    codes = []
    ary.each{|v| codes << v.code }
    assert_equal [code], codes
  end

  def test_array_inject
    ary = ["string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    codes = []
    codes = ary.inject(codes){|acc,v| acc.push(v.code) }
    assert_equal [code], codes
  end

  def test_array_collect
    ary = ["string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    codes = ary.collect{|v| v.code }
    assert_equal [code], codes
  end

  def test_array_collect_no_block
    ary = ["string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    codes = ary.collect
    assert_equal ["string"], codes
  end

  def test_compact
    ary = [nil,"string"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    assert_equal code, ary.compact.first.code
  end

  def test_reverse
    ary = ["string2", "string1"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    assert_equal code, ary.reverse.first.code
    assert_equal "string1", ary.reverse.first
  end

  def test_purge
    ary = ["string2", "string1"]
    code = "Annotation String"
    ExtensionClass.setup(ary, code)
    ary.extend ExtendedArray

    assert MetaExtension.is_extended?(ary)
    assert MetaExtension.is_extended?(ary.first)

    ary = MetaExtension.purge(ary)

    refute MetaExtension.is_extended?(ary)
    refute MetaExtension.is_extended?(ary.first)

  end
end

