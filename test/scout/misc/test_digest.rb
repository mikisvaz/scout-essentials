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
end

