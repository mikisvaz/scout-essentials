require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/annotation'

class TestAnnotationDupClone < Test::Unit::TestCase
  module AnnotSetupA
    extend Annotation
    annotation :organism, :tissue
  end

  def test_dup_strips_annotations_clone_keeps
    a = AnnotSetupA.setup('S004', 'Human', 'Liver')
    assert Annotation.is_annotated?(a)

    d = a.dup
    assert ! Annotation.is_annotated?(d)
    assert_equal 'S004', d

    c = a.clone
    assert Annotation.is_annotated?(c)
    assert_equal 'Human', c.organism
  end

  def test_setup_on_frozen_object_returns_new_annotated_copy
    a = 'S007'.freeze
    r = AnnotSetupA.setup(a, organism: 'Human')
    assert ! Annotation.is_annotated?(a)      # original untouched
    assert a.frozen?
    assert Annotation.is_annotated?(r)        # result is a new, annotated copy
    assert_equal 'Human', r.organism
  end
end
