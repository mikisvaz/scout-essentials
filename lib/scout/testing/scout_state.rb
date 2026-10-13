# Opt-in Scout global-state isolation for tests.
require_relative '../testing'
require_relative '../tmpfile'
require_relative '../persist'
require_relative '../open'

module Scout
  module Testing
    class State
      class RestoreError < StandardError
        attr_reader :errors, :original_error

        def initialize(errors, original_error: nil)
          @errors = errors
          @original_error = original_error
          details = errors.map { |error| "#{error.class}: #{error.message}" }.join('; ')
          message = "Failed to restore #{errors.length} state binding(s): #{details}"
          message += " (while handling #{original_error.class}: #{original_error.message})" if original_error
          super(message)
        end
      end

      def initialize(root, bindings: [])
        @root = File.expand_path(root)
        @bindings = normalize_bindings(bindings)
      end

      def activate
        raise RuntimeError, 'State is already active' if @saved

        @saved = {}
        @activated_bindings = []
        begin
          [[TmpFile, :@tmpdir], [Persist, :@cache_dir], [Persist, :@lock_dir],
           [Open, :@remote_cache_dir], [Open, :@sensible_write_dir],
           [Open, :@sensible_write_lock_dir]].each do |owner, ivar|
            @saved[[owner, ivar]] = [owner.instance_variable_defined?(ivar), owner.instance_variable_get(ivar)]
          end
          @binding_snapshots = @bindings.to_h do |binding|
            [binding, [binding[:owner].instance_variable_defined?(binding[:ivar]),
                       binding[:owner].instance_variable_get(binding[:ivar])]]
          end
          @memory_cache = Persist::MEMORY_CACHE.dup

          FileUtils.mkdir_p(@root)
          @root = File.realpath(@root)
          TmpFile.tmpdir = File.join(@root, 'tmpfiles')
          Persist.cache_dir = File.join(@root, 'persistence-cache')
          Persist.lock_dir = File.join(@root, 'persistence-locks')
          Open.remote_cache_dir = File.join(@root, 'remote-cache')
          Open.sensible_write_dir = File.join(@root, 'sensible-write')
          Open.sensible_write_lock_dir = File.join(@root, 'sensible-write-locks')
          @bindings.each do |binding|
            binding[:target] = File.expand_path(binding[:relative_path], @root)
            create_binding_directory(binding[:target])
            @activated_bindings << binding
            binding[:owner].public_send(binding[:writer], binding[:target])
          end
          Persist::MEMORY_CACHE.clear
          self
        rescue Exception => activation_error
          begin
            restore
          rescue State::RestoreError => restore_error
            raise State::RestoreError.new(restore_error.errors, original_error: activation_error)
          end
          raise
        end
      end

      def restore
        return self unless @saved

        errors = []
        @activated_bindings.reverse_each do |binding|
          was_defined, value = @binding_snapshots.fetch(binding)
          begin
            # Accessor-backed bindings are intended for simple settings whose
            # backing instance variable is the conventional @<accessor>.
            binding[:owner].public_send(binding[:writer], value) if was_defined
          rescue Exception => error
            errors << error
          ensure
            begin
              if was_defined
                binding[:owner].instance_variable_set(binding[:ivar], value)
              elsif binding[:owner].instance_variable_defined?(binding[:ivar])
                binding[:owner].remove_instance_variable(binding[:ivar])
              end
            rescue Exception => error
              errors << error
            end
          end
        end

        @saved.each do |(owner, ivar), (was_defined, value)|
          begin
            if was_defined
              owner.instance_variable_set(ivar, value)
            elsif owner.instance_variable_defined?(ivar)
              owner.remove_instance_variable(ivar)
            end
          rescue Exception => error
            errors << error
          end
        end
        begin
          Persist::MEMORY_CACHE.replace(@memory_cache) if @memory_cache
        rescue Exception => error
          errors << error
        ensure
          @saved = nil
          @binding_snapshots = nil
          @activated_bindings = nil
          @memory_cache = nil
        end

        raise RestoreError, errors unless errors.empty?
        self
      end

      private

      def create_binding_directory(target)
        prefix = "#{@root}#{File::SEPARATOR}"
        raise ArgumentError, "binding path must stay under state root: #{target}" unless target.start_with?(prefix)

        relative = target.delete_prefix(prefix)
        current = @root
        relative.split(File::SEPARATOR).each do |part|
          current = File.join(current, part)
          raise ArgumentError, "binding path traverses a symlink: #{current}" if File.symlink?(current)

          begin
            Dir.mkdir(current)
          rescue Errno::EEXIST
            raise unless File.directory?(current) && !File.symlink?(current)
          end
          raise ArgumentError, "binding path is not a directory: #{current}" unless File.directory?(current) && !File.symlink?(current)
        end
      end

      def normalize_bindings(bindings)
        raise ArgumentError, 'bindings must be an Array' unless Array === bindings

        seen = {}
        bindings.map do |binding|
          unless Array === binding && binding.length == 3
            raise ArgumentError, 'each binding must be [owner, accessor, relative_path]'
          end
          owner, accessor, relative_path = binding
          unless owner.respond_to?(:instance_variable_defined?) && Symbol === accessor &&
              accessor.to_s.match?(/\A[a-zA-Z_]\w*\z/)
            raise ArgumentError, "invalid state binding owner or accessor: #{binding.inspect}"
          end
          writer = "#{accessor}=".to_sym
          raise ArgumentError, "#{owner} does not respond to #{writer}" unless owner.respond_to?(writer)
          unless String === relative_path && !relative_path.empty? && !relative_path.start_with?(File::SEPARATOR)
            raise ArgumentError, "binding path must be a non-empty relative path: #{relative_path.inspect}"
          end
          target = File.expand_path(relative_path, @root)
          unless target.start_with?(@root.end_with?(File::SEPARATOR) ? @root : "#{@root}#{File::SEPARATOR}")
            raise ArgumentError, "binding path must stay under state root: #{relative_path.inspect}"
          end
          key = [owner, accessor]
          raise ArgumentError, "duplicate state binding: #{owner}.#{accessor}" if seen[key]
          seen[key] = true
          { owner: owner, accessor: accessor, writer: writer,
            ivar: "@#{accessor}".to_sym, target: target, relative_path: relative_path }
        end
      end
    end

    module_function

    def with_isolated_state(root, bindings: [])
      state = State.new(root, bindings: bindings)
      begin
        state.activate
        yield state
      rescue Exception => original_error
        begin
          state.restore
        rescue State::RestoreError => restore_error
          raise State::RestoreError.new(restore_error.errors, original_error: original_error)
        end
        raise
      else
        state.restore
      end
    end
  end
end
