require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMetaExtension < Test::Unit::TestCase

  module EmptyExtensionClass
    extend MetaExtension
  end

  module ExtensionClass
    extend MetaExtension

    extension_attr :code, :code2
  end

  module ExtensionClass2
    extend MetaExtension

    extension_attr :code3, :code4
  end

  module ExtensionClassInherit
    extend MetaExtension

    extension_attr :code_pre

    include ExtensionClass
    include ExtensionClass2

    extension_attr :code5
  end

  def test_setup_annotate
    str = "String"
    refute MetaExtension.is_extended?(str)
    ExtensionClass.setup(str, :code)
    assert ExtensionClass === str
    assert MetaExtension.is_extended?(str)
    assert_equal :code, str.code

    str2 = "String2"
    str.annotate(str2)
    assert_equal :code, str2.code
  end

  def test_inheritance
    str = "String"
    ExtensionClass.setup(str, :c, :c2)
    assert_equal :c, str.code

    str = "String"
    ExtensionClassInherit.setup(str, :c_pre, :c, :c2, :c3, :c4, :c5)
    assert_equal :c_pre, str.code_pre
    assert_equal :c, str.code
    assert_equal :c4, str.code4
    assert_equal :c5, str.code5
  end

  def test_setup_annotate_double
    str = "String"
    ExtensionClass.setup(str, :c, :c2)
    ExtensionClass2.setup(str, :c3, :c4)
    assert MetaExtension.is_extended?(str)
    assert ExtensionClass === str
    assert ExtensionClass2 === str
    assert_equal :c, str.code
    assert_equal :c2, str.code2
    assert_equal :c3, str.code3
    assert_equal :c4, str.code4

    str2 = "String2"
    str.annotate(str2)
    assert MetaExtension.is_extended?(str2)
    assert ExtensionClass === str2
    assert ExtensionClass2 === str2
    assert_equal :c, str2.code
    assert_equal :c2, str2.code2
    assert_equal :c3, str2.code3
    assert_equal :c4, str2.code4
  end

  def test_marshal
    str = "String"
    ExtensionClass.setup(str, :code)
    assert ExtensionClass === str
    assert_equal :code, str.code

    str2 = Marshal.load(Marshal.dump(str))
    assert_equal :code, str2.code
  end

  def test_setup_alternatives
    str = "String"

    ExtensionClass.setup(str, nil, :code)
    assert_equal nil, str.code
    assert_equal :code, str.code2

    ExtensionClass.setup(str, :code2 => :code)
    assert_equal :code, str.code2

    ExtensionClass.setup(str, code2: :code)
    assert_equal :code, str.code2

    ExtensionClass.setup(str, "code2" => :code)
    assert_equal :code, str.code2
  end

  def test_setup_block
    o = ExtensionClass.setup nil, :code => :c, :code2 => :c2 do
      puts 1
    end

    assert o.extension_attr_hash.include?(:code)
    assert o.extension_attr_hash.include?(:code2)
  end

  def test_twice
    str = "String"

    ExtensionClass.setup(str, :code2 => :code)
    assert_equal :code, str.code2
    assert_include str.instance_variable_get(:@extension_attrs), :code

    str.extend ExtensionClass2
    str.code3 = :code_alt
    assert_equal :code, str.code2
    assert_equal :code_alt, str.code3
    assert_include str.instance_variable_get(:@extension_attrs), :code
    assert_include str.instance_variable_get(:@extension_attrs), :code3

    assert_include str.extension_attr_hash, :code
    assert_include str.extension_attr_hash, :code3
  end

  def test_extension_types
    str = "String"
    ExtensionClass.setup(str, :code)
    assert ExtensionClass === str
    assert_include str.extension_types, ExtensionClass
  end

  def test_meta_setup
    str = "String"
    MetaExtension.setup(str, [ExtensionClass], code: 'Some code')

    assert_equal 'Some code', str.code
  end

  def test_empty
    refute EmptyExtensionClass.setup("foo").nil?
  end
end

