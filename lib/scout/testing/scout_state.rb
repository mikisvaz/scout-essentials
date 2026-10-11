# Opt-in Scout global-state isolation for tests.
require_relative '../testing'
require_relative '../tmpfile'
require_relative '../persist'
require_relative '../open'

module Scout
  module Testing
    class State
      def initialize(root)
        @root = File.expand_path(root)
      end

      def activate
        @saved = {}
        [[TmpFile, :@tmpdir], [Persist, :@cache_dir], [Persist, :@lock_dir],
         [Open, :@remote_cache_dir], [Open, :@sensible_write_dir],
         [Open, :@sensible_write_lock_dir]].each do |owner, ivar|
          @saved[[owner, ivar]] = [owner.instance_variable_defined?(ivar), owner.instance_variable_get(ivar)]
        end
        @memory_cache = Persist::MEMORY_CACHE.dup
        FileUtils.mkdir_p(@root)
        TmpFile.tmpdir = File.join(@root, 'tmpfiles')
        Persist.cache_dir = File.join(@root, 'persistence-cache')
        Persist.lock_dir = File.join(@root, 'persistence-locks')
        Open.remote_cache_dir = File.join(@root, 'remote-cache')
        Open.sensible_write_dir = File.join(@root, 'sensible-write')
        Open.sensible_write_lock_dir = File.join(@root, 'sensible-write-locks')
        Persist::MEMORY_CACHE.clear
        self
      end

      def restore
        return unless @saved
        @saved.each do |(owner, ivar), (was_defined, value)|
          if was_defined
            owner.instance_variable_set(ivar, value)
          elsif owner.instance_variable_defined?(ivar)
            owner.remove_instance_variable(ivar)
          end
        end
        Persist::MEMORY_CACHE.replace(@memory_cache) if @memory_cache
        @saved = nil
        self
      end
    end

    module_function

    def with_isolated_state(root)
      state = State.new(root)
      begin
        state.activate
        yield state
      ensure
        state.restore
      end
    end
  end
end
