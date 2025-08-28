require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestHook < Test::Unit::TestCase
  def test_hook
    m = Module.new do
      def self.test
        "original"
      end
      
      def test
        'ORIGINAL'
      end
    end

    a = 's'.dup
    a.extend m

    assert_equal 'original', m.test
    assert_equal 'ORIGINAL', a.test

    h = Module.new do
      extend Hook
      def self.test
        "hook"
      end

      def test
        'HOOK'
      end
    end
    
    Hook.apply(h, m)

    a = 's'.dup
    a.extend m

    assert_equal 'hook', m.test
    assert_equal 'HOOK', a.test
  end
end

