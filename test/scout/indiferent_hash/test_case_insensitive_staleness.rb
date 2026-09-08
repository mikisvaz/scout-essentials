require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/indiferent_hash/case_insensitive'

class TestCaseInsensitiveHashStaleness < Test::Unit::TestCase
  def test_miss_then_write_leaves_key_invisible
    ci = CaseInsensitiveHash.setup({'Key' => 1})
    assert_nil ci['fourth']       # builds the downcase map without "Fourth"
    ci['Fourth'] = 9              # plain Hash#[]= does not invalidate the map
    assert_equal 9, ci['Fourth']  # exact lookup still works
    assert_nil ci['fourth']       # but case-insensitive lookup is stale
  end

  def test_symbol_key_added_after_a_miss_is_invisible
    ci = CaseInsensitiveHash.setup({'Key' => 1})
    assert_nil ci['absent']     # miss freezes the downcase map
    ci[:third] = 7              # added after the freeze
    assert_equal 7, ci[:third]  # symbol lookup is exact and works
    assert_nil ci['third']      # string lookup is stale
  end

  def test_read_side_only
    ci = CaseInsensitiveHash.setup({'Key' => 1})
    ci['Other'] = 5
    assert_equal 5, ci['other']
    assert_equal 5, ci['OTHER']
  end
end
