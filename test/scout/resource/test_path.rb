require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/resource'
require 'scout/resource/scout'

class TestResourcePath < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource_alt')

    claim self.tmp.test.string, :string, "TEST"
  end

  def teardown
    FileUtils.rm_rf TestResource.root.find
  end

  def test_read
    assert_include TestResource.tmp.test.string.read, "TEST"
  end

  def test_open
    str = ""
    TestResource.tmp.test.string.open do |f|
      str = f.read
    end
    assert_include str, "TEST"
  end

  def test_write
    TmpFile.with_file do |tmpfile|
      Path.setup(tmpfile)
      tmpfile.foo.bar.write do |f|
        f.puts "TEST"
      end
      assert_include tmpfile.foo.bar.read, "TEST"
    end
  end

  def test_identify
    p = Scout.data.file.find(:lib)
    assert p.located?
    assert_equal "data/file", p.identify
  end

  def test_with_extension
    dir = tmpdir.directory[__method__]
    list = %w(a b)
    Misc.in_dir(dir) do
      file = dir.foo
      Open.write(file.set_extension('list'), list * "\n")
      assert_equal list, file.list
    end
  end
end

