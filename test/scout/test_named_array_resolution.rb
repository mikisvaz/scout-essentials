require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/named_array'

class TestNamedArrayResolution < Test::Unit::TestCase
  def test_exact_match_wins_over_parenthesized_field
    names = ['id', 'Organism', 'Organism (Human)']
    assert_equal 0, NamedArray.identify_name(names, 'id')
    assert_equal 1, NamedArray.identify_name(names, 'Organism')
  end

  def test_paren_fuzzy_match
    names = ['Organism (Human)']
    assert_equal 0, NamedArray.identify_name(names, 'Human')
    # and the other direction
    names = ['Human']
    assert_equal 0, NamedArray.identify_name(names, 'Organism (Human)')
  end

  def test_space_prefix_fuzzy_match
    names = ['Sample id']
    assert_equal 0, NamedArray.identify_name(names, 'Sample')
    names = ['Sample']
    assert_equal 0, NamedArray.identify_name(names, 'Sample id')
  end

  def test_fuzzy_match_is_case_sensitive
    names = ['Alpha']
    assert_nil NamedArray.identify_name(names, 'alpha')
  end

  def test_numeric_string_resolves_as_position
    names = %w(a b c)
    assert_equal 2, NamedArray.identify_name(names, '2')
  end

  def test_unknown_name_reads_nil_and_writes_noop
    row = NamedArray.setup([1, 2, 3], [:a, :b, :c])
    assert_nil row[:nope]
    assigned = (row['nope'] = 4)
    assert_equal 4, assigned            # assignment expression returns value
    assert_equal 3, row.length          # but nothing was stored
    assert_nil row.positions('nope')
  end

  def test_values_at_on_unknown_name_raises_type_error
    row = NamedArray.setup([1, 2, 3], [:a, :b, :c])
    assert_raise(TypeError) { row.values_at('nope') }
  end
end
