require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestAnnotation < Test::Unit::TestCase

  module EmptyAnnotationClass
    extend Annotation
  end

  module AnnotationClass
    extend Annotation

    annotation :code, :code2
  end

  module AnnotationClass2
    extend Annotation

    annotation :code3, :code4
  end

  module AnnotationClassInherit
    extend Annotation

    annotation :code_pre

    include AnnotationClass
    include AnnotationClass2

    annotation :code5
  end

  def test_setup_annotate
    str = "String"
    refute Annotation.is_annotated?(str)
    AnnotationClass.setup(str, :code)
    assert AnnotationClass === str
    assert Annotation.is_annotated?(str)
    assert_equal :code, str.code

    str2 = "String2"
    str.annotate(str2)
    assert_equal :code, str2.code
  end

  def test_inheritance
    str = "String"
    AnnotationClass.setup(str, :c, :c2)
    assert_equal :c, str.code

    str = "String"
    AnnotationClassInherit.setup(str, :c_pre, :c, :c2, :c3, :c4, :c5)
    assert_equal :c_pre, str.code_pre
    assert_equal :c, str.code
    assert_equal :c4, str.code4
    assert_equal :c5, str.code5
  end

  def test_setup_annotate_double
    str = "String"
    AnnotationClass.setup(str, :c, :c2)
    AnnotationClass2.setup(str, :c3, :c4)
    assert Annotation.is_annotated?(str)
    assert AnnotationClass === str
    assert AnnotationClass2 === str
    assert_equal :c, str.code
    assert_equal :c2, str.code2
    assert_equal :c3, str.code3
    assert_equal :c4, str.code4

    str2 = "String2"
    str.annotate(str2)
    assert Annotation.is_annotated?(str2)
    assert AnnotationClass === str2
    assert AnnotationClass2 === str2
    assert_equal :c, str2.code
    assert_equal :c2, str2.code2
    assert_equal :c3, str2.code3
    assert_equal :c4, str2.code4
  end

  def test_marshal
    str = "String"
    AnnotationClass.setup(str, :code)
    assert AnnotationClass === str
    assert_equal :code, str.code

    str2 = Marshal.load(Marshal.dump(str))
    assert_equal :code, str2.code
  end

  def test_setup_alternatives
    str = "String"

    AnnotationClass.setup(str, nil, :code)
    assert_equal nil, str.code
    assert_equal :code, str.code2

    AnnotationClass.setup(str, :code2 => :code)
    assert_equal :code, str.code2

    AnnotationClass.setup(str, code2: :code)
    assert_equal :code, str.code2

    AnnotationClass.setup(str, "code2" => :code)
    assert_equal :code, str.code2
  end

  def test_setup_block
    o = AnnotationClass.setup nil, :code => :c, :code2 => :c2 do
      puts 1
    end

    assert o.annotation_hash.include?(:code)
    assert o.annotation_hash.include?(:code2)
  end

  def test_twice
    str = "String"

    AnnotationClass.setup(str, :code2 => :code)
    assert_equal :code, str.code2
    assert_include str.instance_variable_get(:@annotations), :code

    str.extend AnnotationClass2
    str.code3 = :code_alt
    assert_equal :code, str.code2
    assert_equal :code_alt, str.code3
    assert_include str.instance_variable_get(:@annotations), :code
    assert_include str.instance_variable_get(:@annotations), :code3

    assert_include str.annotation_hash, :code
    assert_include str.annotation_hash, :code3
  end

  def test_annotation_types
    str = "String"
    AnnotationClass.setup(str, :code)
    assert AnnotationClass === str
    assert_include str.annotation_types, AnnotationClass
  end

  def test_meta_setup
    str = "String"
    Annotation.setup(str, [AnnotationClass], code: 'Some code')

    assert_equal 'Some code', str.code
  end

  def test_empty
    refute EmptyAnnotationClass.setup("foo").nil?
  end

  def test_dump
    a = AnnotationClass.setup("a", code: 'test1', code2: 'test2')
    d = Marshal.dump(a)
    a2 = Marshal.load(d)
    assert_equal 'test1', a2.code
  end

  def test_dump_array
    a = AnnotationClass.setup(["a"], code: 'test1', code2: 'test2')
    a.extend AnnotatedArray
    d = Marshal.dump(a)
    a2 = Marshal.load(d)
    assert_equal 'test1', a2.first.code
  end
end

