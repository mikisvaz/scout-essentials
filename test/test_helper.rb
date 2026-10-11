require 'simplecov'

module SimpleCov::Configuration
  def clean_filters
    @filters = []
  end
end

SimpleCov.configure do
  clean_filters
  load_adapter 'test_frameworks'
end

ENV["COVERAGE"] && SimpleCov.start do
  add_filter "/.rvm/"
end
require 'rubygems'
require 'test/unit'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'scout/tmpfile'
require 'scout/log'
require 'scout/open'
require 'scout/persist'
require 'scout/testing'
require 'scout/testing/scout_state'

class Test::Unit::TestCase
  include Scout::Testing::Assertions

  def tmpdir
    @tmpdir ||= Path.setup(Scout::Testing.create_tmpdir(
      parent: File.expand_path('../tmp/test-runs', __dir__),
      prefix: "#{self.class.name}-"
    ))
  end

  setup do
    @scout_testing_state = Scout::Testing::State.new(tmpdir).activate
    @saved_progress_severity = [
      Log::ProgressBar.instance_variable_defined?(:@default_severity),
      Log::ProgressBar.instance_variable_get(:@default_severity)
    ]
    Log::ProgressBar.default_severity = 0
  end

  teardown do
    begin
      @scout_testing_state.restore if @scout_testing_state
    ensure
      if @saved_progress_severity
        existed, value = @saved_progress_severity
        if existed
          Log::ProgressBar.instance_variable_set(:@default_severity, value)
        elsif Log::ProgressBar.instance_variable_defined?(:@default_severity)
          Log::ProgressBar.remove_instance_variable(:@default_severity)
        end
      end
      Scout::Testing.remove_tmpdir(@tmpdir) if @tmpdir
    end
  end
end
