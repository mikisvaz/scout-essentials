require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestOpenSync < Test::Unit::TestCase
  def test_rsync_basic
    TmpFile.with_file do |source|
      TmpFile.with_file do |target|
        Open.write(source, 'payload')
        Open.rsync(source, target)
        assert_equal 'payload', Open.read(target)
      end
    end
  end

  def test_rsync_dir
    TmpFile.with_path do |source|
      TmpFile.with_path do |target|
        Open.write(source.file, 'payload')
        Open.rsync(source, target)
        assert_equal 'payload', Open.read(target.file)
      end
    end
  end

  def test_rsync_excludes
    TmpFile.with_path do |source|
      TmpFile.with_path do |target|
        Open.write(source.file, 'payload')
        Open.write(source.tmp_dir.tmp_file, 'decoy')
        Open.rsync(source, target, excludes: 'tmp_dir')
        assert_equal 'payload', Open.read(target.file)
        refute Open.exist?(target.tmp_dir.tmp_file)
      end
    end
  end

  def test_rsync_remote
    TmpFile.with_path do |source|
      Open.write(source.file, 'payload')
      cmd = Open.rsync(source, 'remote:target', print: true)
      assert cmd.end_with?('remote:target/\'')
    end
  end

  def test_sync_alias
    TmpFile.with_path do |source|
      TmpFile.with_path do |target|
        Open.write(source.file, 'payload')
        Open.sync(source, target)
        assert_equal 'payload', Open.read(target.file)
      end
    end
  end
end

