require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')

class TestOpenForcedGzipBroken < Test::Unit::TestCase
  # Regression test: :gzip => true must NOT be used to force decompression.
  # The option is forwarded to CMD.cmd('gzip', ...) as a command-line flag,
  # producing `gzip --gzip` which fails; :no_fail swallows the failure and
  # the caller silently gets an empty string.
  def test_forced_gzip_returns_empty_string
    TmpFile.with_file("a\nb\n") do |file|
      `gzip #{file}`
      gz = file + '.gz'

      # automatic detection works
      assert_equal "a\nb\n", Open.read(gz)

      # forcing with :gzip on the same file yields "" (documented behaviour)
      assert_equal '', Open.read(gz, :gzip => true)

      # and on a plain file too
      TmpFile.with_file("plain\n") do |plain|
        assert_equal '', Open.read(plain, :gzip => true)
      end
    end
  end
end
