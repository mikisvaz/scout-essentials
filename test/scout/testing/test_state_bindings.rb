require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/testing/scout_state'

module TestStateBindingSettings
  class << self
    attr_accessor :first_root, :second_root
  end
end

class TestScoutTestingStateBindings < Test::Unit::TestCase
  Settings = TestStateBindingSettings

  def setup
    super
    Settings.instance_variable_set(:@first_root, 'before-first')
    Settings.instance_variable_set(:@second_root, 'before-second')
  end

  def teardown
    Settings.remove_instance_variable(:@first_root) if Settings.instance_variable_defined?(:@first_root)
    Settings.remove_instance_variable(:@second_root) if Settings.instance_variable_defined?(:@second_root)
    super
  end

  def test_multiple_bindings_use_root_subdirectories_and_restore_old_values
    root = File.join(tmpdir, 'bound-state')
    bindings = [
      [Settings, :first_root, 'workflow'],
      [Settings, :second_root, 'jobs/cache']
    ]

    Scout::Testing.with_isolated_state(root, bindings: bindings) do
      assert_equal File.join(root, 'workflow'), Settings.first_root
      assert_equal File.join(root, 'jobs/cache'), Settings.second_root
      assert File.directory?(Settings.first_root)
      assert File.directory?(Settings.second_root)
    end

    assert_equal 'before-first', Settings.first_root
    assert_equal 'before-second', Settings.second_root
  end

  def test_binding_restores_an_originally_unset_accessor
    Settings.remove_instance_variable(:@first_root)

    Scout::Testing.with_isolated_state(File.join(tmpdir, 'unset-state'),
      bindings: [[Settings, :first_root, 'cache']]) { }

    refute Settings.instance_variable_defined?(:@first_root)
  end

  def test_block_exception_restores_bindings_and_preserves_original_exception
    error = assert_raise(RuntimeError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'exception-state'),
        bindings: [[Settings, :first_root, 'cache']]) do
        raise 'block failure'
      end
    end

    assert_equal 'block failure', error.message
    assert_equal 'before-first', Settings.first_root
  end

  def test_activation_setter_failure_restores_all_activated_bindings
    singleton = Settings.singleton_class
    singleton.alias_method :second_root_set_for_test, :second_root=
    singleton.define_method(:second_root=) do |value|
      if value.end_with?('/cache')
        @second_root = value
        raise 'setter activation failure'
      end
      self.second_root_set_for_test(value)
    end

    error = assert_raise(RuntimeError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'setter-failure'), bindings: [
        [Settings, :first_root, 'first-cache'],
        [Settings, :second_root, 'cache']
      ]) { flunk 'block should not run' }
    end
    assert_equal 'setter activation failure', error.message
    assert_equal 'before-first', Settings.first_root
    assert_equal 'before-second', Settings.second_root
  ensure
    if singleton && singleton.method_defined?(:second_root_set_for_test)
      singleton.alias_method :second_root=, :second_root_set_for_test
      singleton.remove_method :second_root_set_for_test
    end
  end

  def test_restore_tries_other_bindings_and_reports_setter_error
    singleton = Settings.singleton_class
    singleton.alias_method :first_root_set_for_test, :first_root=
    singleton.define_method(:first_root=) do |value|
      raise 'cannot restore first' if value == 'before-first'
      self.first_root_set_for_test(value)
    end

    error = assert_raise(Scout::Testing::State::RestoreError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'restore-failure'), bindings: [
        [Settings, :first_root, 'cache-one'],
        [Settings, :second_root, 'cache-two']
      ]) { }
    end

    assert_match(/cannot restore first/, error.message)
    assert_equal 'before-first', Settings.first_root # fallback restores conventional backing ivar
    assert_equal 'before-second', Settings.second_root # later binding still restored
    assert_equal 1, error.errors.length
  ensure
    if singleton && singleton.method_defined?(:first_root_set_for_test)
      singleton.alias_method :first_root=, :first_root_set_for_test
      singleton.remove_method :first_root_set_for_test
    end
  end

  def test_restore_error_keeps_the_original_block_exception
    singleton = Settings.singleton_class
    singleton.alias_method :first_root_set_for_test, :first_root=
    singleton.define_method(:first_root=) do |value|
      raise 'cannot restore first' if value == 'before-first'
      self.first_root_set_for_test(value)
    end

    error = assert_raise(Scout::Testing::State::RestoreError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'restore-with-block-error'),
        bindings: [[Settings, :first_root, 'cache']]) do
        raise 'original block error'
      end
    end

    assert_equal 'original block error', error.original_error.message
    assert_equal 'before-first', Settings.first_root
  ensure
    if singleton && singleton.method_defined?(:first_root_set_for_test)
      singleton.alias_method :first_root=, :first_root_set_for_test
      singleton.remove_method :first_root_set_for_test
    end
  end

  def test_binding_refuses_symlink_components_under_state_root
    root = File.join(tmpdir, 'symlink-state')
    outside = File.join(tmpdir, 'outside-state')
    FileUtils.mkdir_p(root)
    FileUtils.mkdir_p(outside)
    File.symlink(outside, File.join(root, 'linked'))

    assert_raise(ArgumentError) do
      Scout::Testing.with_isolated_state(root,
        bindings: [[Settings, :first_root, 'linked/nested']]) { flunk 'block should not run' }
    end
    refute File.exist?(File.join(outside, 'nested'))
  end

  def test_binding_rejects_absolute_and_root_escaping_paths
    assert_raise(ArgumentError) do
      Scout::Testing::State.new(tmpdir, bindings: [[Settings, :first_root, '/tmp/outside']])
    end
    assert_raise(ArgumentError) do
      Scout::Testing::State.new(tmpdir, bindings: [[Settings, :first_root, '../outside']])
    end
  end
end
