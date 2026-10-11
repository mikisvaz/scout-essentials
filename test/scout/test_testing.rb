require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/testing'
require 'scout/testing/scout_state'

class TestScoutTesting < Test::Unit::TestCase
  def test_tmpdir_is_unique_and_ensure_cleaned
    paths = []
    assert_raise(RuntimeError) do
      Scout::Testing.with_tmpdir(parent: tmpdir) do |path|
        paths << path
        File.write(File.join(path, 'real-file'), 'fixture')
        assert_equal 'fixture', File.read(File.join(path, 'real-file'))
        raise 'expected'
      end
    end
    refute File.exist?(paths.first)

    first = Scout::Testing.create_tmpdir(parent: tmpdir)
    second = Scout::Testing.create_tmpdir(parent: tmpdir)
    refute_equal first, second
    assert File.directory?(first)
    assert File.directory?(second)
    Scout::Testing.remove_tmpdir(first)
    Scout::Testing.remove_tmpdir(second)
  end

  def test_fixture_paths_resolve_non_git_consumer_from_file_and_directory
    Scout::Testing.with_tmpdir(parent: Dir.tmpdir) do |root|
      test_directory = File.join(root, 'test', 'scout')
      test_file = File.join(test_directory, 'test_consumer.rb')
      fixture_file = File.join(root, 'test', 'fixtures', 'example.txt')
      FileUtils.mkdir_p(test_directory)
      FileUtils.mkdir_p(File.dirname(fixture_file))
      File.write(test_file, '# synthetic non-Git consumer')
      File.write(fixture_file, 'consumer fixture')
      refute File.exist?(File.join(root, '.git'))

      assert_equal root, Scout::Testing.repository_root(test_file)
      assert_equal root, Scout::Testing.repository_root(test_directory)
      assert_equal File.join(root, 'test/fixtures'),
        Scout::Testing.fixture_root(from: test_file)
      assert_equal fixture_file,
        Scout::Testing.fixture_path('example.txt', from: test_file)
      assert_equal 'consumer fixture',
        File.read(Scout::Testing.fixture_path('example.txt', from: test_file))
    end
  end

  def test_repository_root_git_and_non_git_directory_inputs
    repository = File.expand_path('../..', __dir__)
    assert_equal repository, Scout::Testing.repository_root(__dir__)
    assert_equal repository, Scout::Testing.repository_root(__FILE__)

    Scout::Testing.with_tmpdir(parent: Dir.tmpdir) do |root|
      FileUtils.mkdir_p(File.join(root, 'lib', 'consumer'))
      assert_equal root, Scout::Testing.repository_root(root)
      assert_equal root, Scout::Testing.repository_root(File.join(root, 'lib'))
    end
  end

  def test_path_assertions
    assert Path === tmpdir
    assert_equal_path '.', File.expand_path('.')
    assert_path_exists __FILE__
  end

  def test_generic_require_is_standard_library_only_in_fresh_process
    root = File.expand_path('../..', __dir__)
    lib = File.join(root, 'lib')
    script = <<~'RUBY'
      $LOAD_PATH.unshift ARGV.fetch(1)
      require 'scout/testing'
      forbidden = $LOADED_FEATURES.grep(%r{/scout/(?:tmpfile|persist|open)(?:/|\.rb)})
      abort "Scout components loaded: #{forbidden.join(', ')}" unless forbidden.empty?
      abort 'TmpFile was initialized' if defined?(TmpFile)
      abort 'Persist was initialized' if defined?(Persist)
      puts 'generic-clean'
    RUBY
    output = IO.popen([RbConfig.ruby, '-e', script, root, lib], &:read)
    assert $?.success?, output
    assert_equal "generic-clean\n", output
  end

  def test_generic_source_has_no_scout_component_dependency
    source = File.read(File.expand_path('../../lib/scout/testing.rb', __dir__))
    refute_match(/require.*(?:tmpfile|persist|open)/, source)
    refute_match(/\b(?:TmpFile|Persist|Open)\b/, source)
  end

  def test_state_layer_loads_components_explicitly
    root = File.expand_path('../..', __dir__)
    lib = File.join(root, 'lib')
    script = <<~'RUBY'
      $LOAD_PATH.unshift ARGV.fetch(1)
      require 'scout/testing'
      abort 'TmpFile loaded too early' if defined?(TmpFile)
      require 'scout/testing/scout_state'
      abort 'State API missing' unless Scout::Testing.const_defined?(:State) &&
        Scout::Testing.respond_to?(:with_isolated_state)
      abort 'Scout components missing' unless defined?(TmpFile) && defined?(Persist) && defined?(Open)
      puts 'state-loaded'
    RUBY
    output = IO.popen([RbConfig.ruby, '-e', script, root, lib], &:read)
    assert $?.success?, output
    assert_equal "state-loaded\n", output
  end

  def test_state_restored_after_exception
    Persist::MEMORY_CACHE[:original] = :keep
    prior = state_snapshot
    assert_raise(RuntimeError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'isolated')) do
        assert_equal File.join(tmpdir, 'isolated', 'tmpfiles'), TmpFile.tmpdir
        assert_equal File.join(tmpdir, 'isolated', 'persistence-cache'), Persist.cache_dir.find
        assert_equal File.join(tmpdir, 'isolated', 'persistence-locks'), Persist.lock_dir
        assert_equal File.join(tmpdir, 'isolated', 'remote-cache'), Open.remote_cache_dir
        assert_equal File.join(tmpdir, 'isolated', 'sensible-write'), Open.sensible_write_dir
        assert_equal File.join(tmpdir, 'isolated', 'sensible-write-locks'), Open.sensible_write_lock_dir
        assert_empty Persist::MEMORY_CACHE
        Persist::MEMORY_CACHE[:temporary] = :discard
        raise 'expected'
      end
    end
    assert_state_snapshot prior
  end

  def test_state_restores_unset_and_set_to_nil_instance_variables
    TmpFile.remove_instance_variable(:@tmpdir) if TmpFile.instance_variable_defined?(:@tmpdir)
    Persist.instance_variable_set(:@lock_dir, nil)
    Open.instance_variable_set(:@sensible_write_dir, nil)

    Scout::Testing.with_isolated_state(File.join(tmpdir, 'isolated-nil')) { }

    refute TmpFile.instance_variable_defined?(:@tmpdir)
    assert Persist.instance_variable_defined?(:@lock_dir)
    assert_nil Persist.instance_variable_get(:@lock_dir)
    assert Open.instance_variable_defined?(:@sensible_write_dir)
    assert_nil Open.instance_variable_get(:@sensible_write_dir)
  end

  def test_state_restored_when_activation_raises
    prior = state_snapshot
    singleton = Persist.singleton_class
    singleton.alias_method :cache_dir_set_for_testing, :cache_dir=
    singleton.define_method(:cache_dir=) { |_value| raise 'activation failed' }

    assert_raise(RuntimeError) do
      Scout::Testing.with_isolated_state(File.join(tmpdir, 'activation-failure')) { flunk 'block should not run' }
    end
    assert_state_snapshot prior
  ensure
    if singleton && singleton.method_defined?(:cache_dir_set_for_testing)
      singleton.alias_method :cache_dir=, :cache_dir_set_for_testing
      singleton.remove_method :cache_dir_set_for_testing
    end
  end

  def test_runtime_load_does_not_activate_testing
    root = File.expand_path('../..', __dir__)
    lib = File.join(root, 'lib')
    script = <<~'RUBY'
      $LOAD_PATH.unshift ARGV.fetch(1)
      require 'scout-essentials'
      abort 'testing entrypoint loaded' if $LOADED_FEATURES.any? { |f| f.end_with?('/scout/testing.rb') }
      abort 'testing module defined' if defined?(Scout::Testing)
      puts 'runtime-clean'
    RUBY
    output = IO.popen([RbConfig.ruby, '-e', script, root, lib], &:read)
    assert $?.success?, output
    assert_equal "runtime-clean\n", output
  end

  private

  def state_snapshot
    [[TmpFile, :@tmpdir], [Persist, :@cache_dir], [Persist, :@lock_dir],
     [Open, :@remote_cache_dir], [Open, :@sensible_write_dir],
     [Open, :@sensible_write_lock_dir]].to_h do |owner, ivar|
      [[owner, ivar], [owner.instance_variable_defined?(ivar), owner.instance_variable_get(ivar)]]
    end.merge(memory_cache: Persist::MEMORY_CACHE.dup)
  end

  def assert_state_snapshot(snapshot)
    snapshot.each do |key, value|
      if key == :memory_cache
        assert_equal value, Persist::MEMORY_CACHE
      else
        owner, ivar = key
        existed, saved_value = value
        assert_equal existed, owner.instance_variable_defined?(ivar), "#{owner} #{ivar} definedness"
        assert_equal saved_value, owner.instance_variable_get(ivar) if existed
      end
    end
  end
end
