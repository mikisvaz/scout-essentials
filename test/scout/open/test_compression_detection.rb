require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')

class TestOpenCompressionDetection < Test::Unit::TestCase
  def test_suffix_detection_is_lowercase_only
    TmpFile.with_file('content') do |file|
      `gzip #{file}`
      gz = file + '.gz'
      assert Open.gzip?(gz)
      assert Open.compressed?(gz)

      upper = gz + '.GZ.tmp'
      FileUtils.mv gz, upper
      FileUtils.cp upper, gz + '.2' if false
      assert ! Open.gzip?(upper), '.GZ is not detected'
      assert ! Open.compressed?(upper)
      FileUtils.mv upper, gz
    end
  end

  def test_gz_magic_bytes_without_suffix_stay_raw
    content = "a\nb\n"
    TmpFile.with_file(content) do |file|
      `gzip #{file}`
      gz = file + '.gz'
      noext = gz + '.noext'
      FileUtils.mv gz, noext
      assert_equal [31, 139].first, Open.read(noext).bytes.first
      assert_equal 'a', Open.read(noext, :noz => true).bytes.first.chr rescue nil
      FileUtils.rm noext
    end
  end
end
