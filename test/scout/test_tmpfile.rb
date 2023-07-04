require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestTmpFile < Test::Unit::TestCase

  def test_tmp_file
    assert(TmpFile.tmp_file("test") =~ /(tmpfiles|tmp)\/test\d+$/)
  end

  def test_do_tmp_file
    content = "Hello World!"
    TmpFile.with_file(content) do |file|
      assert_equal content, File.open(file).read
    end
  end

  def test_do_tmp_file_io
    content = "Hello World!"
    TmpFile.with_file(content) do |file1|
      File.open(file1) do |io|
        TmpFile.with_file(io) do |file|
          assert_equal content, File.open(file).read
        end
      end
    end
  end

  def test_extension
    TmpFile.with_file(nil, true, :extension => 'txt') do |file|
      assert file =~ /\.txt$/
    end
  end

  def test_tmpdir
    TmpFile.with_file(nil, true, :tmpdir => TmpFile.user_tmp("TMPDIR")) do |file|
      assert file =~ /TMPDIR/
    end

    TmpFile.tmpdir = TmpFile.user_tmp("TMPDIR")

    TmpFile.with_file do |file|
      assert file =~ /TMPDIR/
    end
  end

  def test_in_dir
    TmpFile.in_dir do |dir|
      assert_equal_path dir, FileUtils.pwd
    end
  end

end

