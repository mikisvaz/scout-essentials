require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout'
class TestResourceSync < Test::Unit::TestCase
  def test_sync_file
    TmpFile.with_path do |source|
      TmpFile.with_path do |target|
        Open.write(source.file, 'payload')
        Misc.in_dir target.find do
          Resource.sync(source.file, :current)
        end

        assert_equal 'payload', Open.read(target[Resource.identify(source)].file)
      end
    end
  end

  def test_sync_dir
    TmpFile.with_path do |source|
      TmpFile.with_path do |target|
        Open.write(source.file, 'payload')
        Misc.in_dir target.find do
          Resource.sync(source, :current)
        end

        assert_equal 'payload', Open.read(target[Resource.identify(source)].file)
      end
    end
  end
end

