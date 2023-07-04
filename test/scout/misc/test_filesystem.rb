require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestFilesystem < Test::Unit::TestCase
  def test_in_dir
    TmpFile.with_file do |tmpdir|
      Misc.in_dir tmpdir do
        assert_equal tmpdir, FileUtils.pwd
      end
    end
  end

  def test_relative
    assert_equal 'bar', Misc.path_relative_to("/tmp/foo", "/tmp/foo/bar")
    assert_equal 'bar/other', Misc.path_relative_to("/tmp/foo", "/tmp/foo/bar/other")

    refute Misc.path_relative_to("/tmp/bar", "/tmp/foo/bar/other")
    refute Misc.path_relative_to("/tmp/foo", "tmp/foo/bar/other")

    TmpFile.with_file do |tmpdir|
      Misc.in_dir tmpdir do
        assert Misc.path_relative_to(tmpdir, "foo")
        assert Misc.path_relative_to(tmpdir, File.join(tmpdir, "foo"))
      end
      assert Misc.path_relative_to(tmpdir, File.join(tmpdir, "foo"))
      assert Misc.path_relative_to(File.dirname(tmpdir), File.join(tmpdir, "foo"))
    end
  end
end

