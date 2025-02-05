require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/path'
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPathUtil < Test::Unit::TestCase
  def test_dirname
    p = Path.setup("/usr/share/scout/data")

    assert_equal "/usr/share/scout", p.dirname
  end

  def test_glob
    TmpFile.in_dir :erase => false do |tmpdir|
      Path.setup tmpdir
      File.write(tmpdir.foo, 'foo')
      File.write(tmpdir.bar, 'bar')
      assert_equal 2, tmpdir.glob.length
      assert_equal %w(foo bar).sort, tmpdir.glob.collect{|p| p.basename }.sort
    end
  end

  def test_unset_extension
    path = Path.setup("/home/.scout/dir/file.txt")
    assert_equal "/home/.scout/dir/file", path.unset_extension

    path = Path.setup("/home/.scout/dir/file")
    assert_equal "/home/.scout/dir/file", path.unset_extension
  end
end

