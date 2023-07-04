require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscSystem < Test::Unit::TestCase
  setup do
    ENV.delete "TEST_VAR"
  end

  def test_env_add
    Misc.env_add "TEST_VAR", "test_value1"
    Misc.env_add "TEST_VAR", "test_value2"
    assert_equal "test_value2:test_value1", ENV["TEST_VAR"]
  end

  def test_env_add_prepend
    Misc.env_add "TEST_VAR", "test_value1", ":", false
    Misc.env_add "TEST_VAR", "test_value2", ":", false
    assert_equal "test_value1:test_value2", ENV["TEST_VAR"]
  end
end

