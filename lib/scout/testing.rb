# Opt-in support for generic test helpers; deliberately not required by scout-essentials.
require 'tmpdir'
require 'fileutils'

module Scout
  module Testing
    module Assertions
      def assert_equal_path(expected, actual, message = nil)
        assert_equal File.expand_path(expected), File.expand_path(actual), message
      end

      def assert_path_exists(path, message = nil)
        assert File.exist?(path), message || "Expected path to exist: #{path}"
      end
    end

    module_function

    def create_tmpdir(parent: Dir.tmpdir, prefix: 'scout-test-')
      FileUtils.mkdir_p(parent)
      Dir.mktmpdir(prefix, parent)
    end

    def remove_tmpdir(path)
      FileUtils.remove_entry(path) if path && File.exist?(path)
    end

    def with_tmpdir(parent: Dir.tmpdir, prefix: 'scout-test-')
      path = create_tmpdir(parent: parent, prefix: prefix)
      begin
        yield path
      ensure
        remove_tmpdir(path)
      end
    end

    # Resolve against the consumer's repository, not this helper's source tree.
    def fixture_root(from:, directory: 'test/fixtures')
      File.expand_path(directory, repository_root(from))
    end

    def fixture_path(*parts, from:, directory: 'test/fixtures')
      File.join(fixture_root(from: from, directory: directory), *parts)
    end

    def repository_root(from)
      start = File.expand_path(from)
      start = File.dirname(start) unless File.directory?(start)
      ancestors = []
      path = start
      loop do
        ancestors << path
        parent = File.dirname(path)
        break if parent == path
        path = parent
      end

      # A Git worktree is authoritative when present, including for paths
      # nested below a consumer's test or lib directory.
      git_root = ancestors.find do |candidate|
        File.directory?(File.join(candidate, '.git')) || File.file?(File.join(candidate, '.git'))
      end
      return git_root if git_root

      # For non-Git consumers, infer the root from the conventional test/ or
      # lib/ layout surrounding the supplied file/directory. This is a
      # heuristic, not a universal repository detector: arbitrary paths with
      # no such marker retain the conservative file-local fallback below.
      layout_directory = ancestors.find { |candidate| %w[test lib].include?(File.basename(candidate)) }
      return File.dirname(layout_directory) if layout_directory

      # Also support a consumer root passed directly (or a directory beneath
      # it) when that root contains a conventional top-level test/ or lib/.
      root_with_layout = ancestors.find do |candidate|
        File.directory?(File.join(candidate, 'test')) || File.directory?(File.join(candidate, 'lib'))
      end
      return root_with_layout if root_with_layout

      File.dirname(File.expand_path(from))
    end
  end
end
