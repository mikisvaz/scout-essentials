require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPath < Test::Unit::TestCase
  def test_join
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path.join(:foo)
    assert_equal '/tmp/foo/bar', path.join(:bar, :foo)
  end

  def test_get
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path[:foo]
    assert_equal '/tmp/foo/bar', path.foo[:bar]
    assert_equal '/tmp/foo/bar', path[:bar, :foo]
  end

  def test_slash
    path = '/tmp'
    path.extend Path
    assert_equal '/tmp/foo', path/:foo
    assert_equal '/tmp/foo/bar', path/:foo/:bar
    assert_equal '/tmp/foo/bar', path.foo/:bar
    assert_equal '/tmp/foo/bar', path./(:bar, :foo)
  end

  def test_setup
    path = 'tmp'
    Path.setup(path)
    assert_equal 'scout', path.pkgdir
    assert path.libdir.end_with?("scout-essentials")
  end

  def test_lib_dir
    TmpFile.with_file do |tmpdir|
      Path.setup tmpdir
      FileUtils.mkdir_p tmpdir.lib
      lib_path = File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')
      lib_path = File.join(Path.caller_lib_dir, 'lib', lib_path)
      File.write tmpdir.lib.file, <<-EOR 
require '#{lib_path}'
a = "1"
Path.setup(a)
print a.libdir
      EOR
      Misc.in_dir tmpdir.tmp do
        assert_equal tmpdir, `ruby #{tmpdir.lib.file}`
      end
    end
  end
end

