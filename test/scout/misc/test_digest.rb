require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestMiscDigest < Test::Unit::TestCase
  def test_digest_str
    o = {:a => [1,2,3], :b => [1.1, 0.00001, 'hola']}
    assert Misc.digest_str(o).include? "hola"
  end

  def test_digest_stream_located
    TmpFile.with_file("TEST") do |filename|
      Open.open(filename) do |f|
        assert_equal 32, Misc.digest_str(f).length
      end
    end
  end

  def test_digest_stream_unlocated
    TmpFile.with_file do |directory|
      Path.setup(directory)
      Open.write(directory.share.file, "TEST")
      Misc.in_dir directory do
        Open.open(Path.setup('share/file')) do |f|
          assert_equal '\'share/file\'', Misc.digest_str(Path.setup('share/file'))
        end
      end
    end
  end

  def test_file_digest
    content1 =<<-EOF
This is one file
    EOF

    content2 =<<-EOF
This is another file
    EOF

    TmpFile.with_file(content1) do |file1|
      TmpFile.with_file(content2) do |file2|
        digest1 = Misc.digest_file(file1)
        digest2 = Misc.digest_file(file2)
        refute_equal digest1, digest2
      end
    end
  end

  def test_file_digest_fast
    content1 =<<-EOF
This is one file
    EOF

    content2 =<<-EOF
This is another file
    EOF

    TmpFile.with_file(content1) do |file1|
      TmpFile.with_file(content2) do |file2|
        digest1 = Misc.fast_file_md5(file1, 5)
        digest2 = Misc.fast_file_md5(file2, 5)
        refute_equal digest1, digest2
      end
    end
  end

  def test_file_digest_fast_2
    content1 =<<-EOF
This is file 2
    EOF

    content2 =<<-EOF
This is file 1
    EOF

    TmpFile.with_file(content1) do |file1|
      TmpFile.with_file(content2) do |file2|
        digest1 = Misc.fast_file_md5(file1, 5)
        digest2 = Misc.fast_file_md5(file2, 5)
        refute_equal digest1, digest2
      end
    end
  end
end

