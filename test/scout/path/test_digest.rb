require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestClass < Test::Unit::TestCase
  def test_digest_path
    TmpFile.with_path("TEXT") do |file|
      assert_include file.digest_str, "File MD5"
    end

    TmpFile.with_path do |dir|
      Open.write(dir.test, "TEXT")
      assert_include dir.digest_str, "Directory"
    end

    TmpFile.with_path do |file|
      assert_include "'#{file}'", file.digest_str
    end
  end
end

