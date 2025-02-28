require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestConfig < Test::Unit::TestCase
  setup do
    Scout::Config.set({:cpus => 30}, :test_config, :test)
    Scout::Config.set(:cpus, 5, "slow::2", :test)
    Scout::Config.set({:token => "token"}, "token")
    Scout::Config.set(:notoken, "no_token")
    Scout::Config.set({:emptytoken => "empty"})
  end

  def test_simple
    assert_equal 30, Scout::Config.get(:cpus, :test_config)
  end

  def test_match
    assert_equal({20 => ["token"]}, Scout::Config.match({["key:token"] => "token"}, "key:token"))
  end

  def test_simple_no_token
    assert_equal "token", Scout::Config.get("token", "token")
    assert_equal "no_token", Scout::Config.get("notoken", "key:notoken")
    assert_equal 'token', Scout::Config.get("token", "key:token")
    assert_equal 'token', Scout::Config.get("token")
    assert_equal nil, Scout::Config.get("token", "someotherthing")
    assert_equal "default_token", Scout::Config.get("token", 'unknown', :default => 'default_token')
    assert_equal 'empty', Scout::Config.get("emptytoken", 'key:emptytoken')
  end

  def test_prio
    assert_equal 5, Scout::Config.get(:cpus, :slow, :test)
  end

  def test_with_config
    Scout::Config.add_entry 'key', 'valueA', 'token'
    assert_equal "valueA", Scout::Config.get('key', 'token')
    assert_equal "default", Scout::Config.get('key2', 'token', :default => 'default')

    Scout::Config.with_config do 
      Scout::Config.add_entry 'key', 'valueB', 'token'
      Scout::Config.add_entry 'key2', 'valueB2', 'token'
      assert_equal "valueB", Scout::Config.get('key', 'token')
      assert_equal "valueB2", Scout::Config.get('key2', 'token', :default => 'default')
    end

    assert_equal "valueA", Scout::Config.get('key', 'token')
    assert_equal "default", Scout::Config.get('key2', 'token', :default => 'default')
  end

  def test_order
    Scout::Config.add_entry 'key', 'V1', 'token1'
    Scout::Config.add_entry 'key', 'V2', 'token2'
    Scout::Config.add_entry 'key', 'V3', 'token2'

    assert_equal "V3", Scout::Config.get('key', 'token2')
    assert_equal "V1", Scout::Config.get('key', 'token1')
    assert_equal "V3", Scout::Config.get('key', 'token2', 'token1')
    assert_equal "V1", Scout::Config.get('key', 'token1', 'token2')
  end

  def test_default
    Scout::Config.add_entry 'key', 'V1', 'token1'
    assert_equal "V3", Scout::Config.get('key', 'token2', :default => 'V3')
  end

  def test_env
    Misc.with_env "TEST_VAR", "TEST" do
      assert_equal "TEST", Scout::Config.get("value", :key, :env => "TEST_VAR")
      Scout::Config.set "value", 'env:TEST_VAR', 'key'
      assert_equal "TEST", Scout::Config.get(:value, :key)
    end
  end

  def test_env_multiple
    Misc.with_env "TEST_VAR", "TEST" do
      assert_equal "TEST", Scout::Config.get("value", :key, :env => "TEST_VAR,TESTVAR")
      Scout::Config.set "value", 'env:TEST_VAR,TESTVAR', 'key'
      assert_equal "TEST", Scout::Config.get(:value, :key)
    end
  end
end
