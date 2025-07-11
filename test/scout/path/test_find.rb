require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'scout/path'
require 'scout/misc'
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPathFind < Test::Unit::TestCase
  def test_parts
    path = Path.setup("share/data/some_file", 'scout')
    assert_equal "share", path._toplevel
    assert_equal "data/some_file", path._subpath

    path = Path.setup("data", 'scout')
    assert_equal "data", path._toplevel
    assert_equal nil, path._subpath
  end

  def test_find_local
    map = File.join('/usr/local', "{TOPLEVEL}", "{PKGDIR}", "{SUBPATH}")
    path = Path.setup("share/data/some_file", 'scout')
    target = "/usr/local/share/scout/data/some_file"
    assert_equal target, Path.follow(path, map)
  end

  def test_find
    path = Path.setup("share/data/some_file", 'scout')
    assert_equal "/usr/share/scout/data/some_file", path.find(:usr)
  end

  def test_current
    path = Path.setup("share/data/some_file", 'scout')
    TmpFile.in_dir do |tmpdir|
      assert_equal_path File.join(tmpdir,"share/data/some_file"),  path.find(:current)
    end
  end

  def test_current_find
    path = Path.setup("share/data/some_file", 'scout')
    TmpFile.in_dir do |tmpdir|
      FileUtils.mkdir_p(File.dirname(File.join(tmpdir, path)))
      File.write(File.join(tmpdir, path), 'string')
      assert_equal_path File.join(tmpdir,"share/data/some_file"),  path.find
      assert_equal :current,  path.find.where
      assert_equal "share/data/some_file",  path.find.original
    end
  end

  def test_current_find_all
    path = Path.setup("share/data/some_file", 'scout')
    TmpFile.with_dir do |tmpdir|
      Path.setup tmpdir

      FileUtils.mkdir_p(tmpdir.lib)
      FileUtils.mkdir_p(tmpdir.share.data)
      File.write(tmpdir.share.data.some_file, 'string')

      FileUtils.mkdir_p(tmpdir.subdir.share.data)
      File.write(tmpdir.subdir.share.data.some_file, 'string')

      path.libdir = tmpdir
      Misc.in_dir tmpdir.subdir do
        assert_equal 2, path.find_all.length
      end
    end
  end

  def test_located?

    p = Path.setup("/tmp/foo/bar")
    assert p.located?
    assert_equal_path p, p.find
  end

  def test_custom
    path = Path.setup("share/data/some_file", 'scout')
    TmpFile.with_file do |tmpdir|
      path.path_maps[:custom] = [tmpdir, '{PATH}'] * "/"
      assert_equal_path File.join(tmpdir,"share/data/some_file"),  path.find(:custom)

      path.path_maps[:custom] = [tmpdir, '{TOPLEVEL}/{PKGDIR}/{SUBPATH}'] * "/"
      assert_equal_path File.join(tmpdir,"share/scout/data/some_file"),  path.find(:custom)
    end
  end

  def test_pkgdir
    path = Path.setup("share/data/some_file", 'scout')
    TmpFile.with_file do |tmpdir|
      path.pkgdir = 'scout_alt'
      path.path_maps[:custom] = [tmpdir, '{TOPLEVEL}/{PKGDIR}/{SUBPATH}'] * "/"
      assert_equal_path File.join(tmpdir,"share/scout_alt/data/some_file"),  path.find(:custom)
    end
  end

  def test_sub
    path = Path.setup("bin/scout/find")

    assert_equal "/some_dir/bin/scout_commands/find",  Path.follow(path, "/some_dir/{PATH/scout/scout_commands}")
    assert_equal "/some_dir/scout_commands/find",  Path.follow(path, '/some_dir/{PATH/bin\/scout/scout_commands}')
  end

  def test_gz
    TmpFile.with_file do |tmpdir|
      Path.setup(tmpdir)
      Open.write(tmpdir.somefile + '.gz', "FOO")
      assert_equal_path tmpdir.somefile + '.gz', tmpdir.somefile.find
      assert Open.exist?(tmpdir.somefile)
    end
  end

  def test_plain_map
    path = Path.setup("somefile")
    TmpFile.with_path do |tmpdir|
      Open.write(tmpdir.somefile, 'test')
      path.add_path :tmpdir, tmpdir
      assert path.exists?
    end
  end

  def test_add_path
    TmpFile.with_path do |dir1|
      TmpFile.with_path do |dir2|
        TmpFile.with_path do |dir3|
          TmpFile.with_path do |dir4|
            Open.write(dir1.foo, "FOO1")
            Open.write(dir2.foo, "FOO2")
            Open.write(dir3.foo, "FOO3")
            Open.write(dir4.foo, "FOO4")
            file = Path.setup('foo')
            file.append_path 'dir1', dir1
            assert_equal "FOO1", Open.read(file)
            file.prepend_path 'dir2', dir2
            assert_equal "FOO2", Open.read(file)
            file.prepend_path 'dir3', dir3
            assert_equal "FOO3", Open.read(file)
            file.append_path 'dir4', dir4
            assert_equal "FOO3", Open.read(file)
          end
        end
      end
    end
  end

  def test_single
    file = Path.setup('foo')
    assert_equal 'foo', file._toplevel
    assert_equal nil, file._subpath
    assert_equal '/usr/local/foo/scout/', file.find(:local)
  end
end

