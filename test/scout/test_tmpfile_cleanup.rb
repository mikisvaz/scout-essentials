require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require 'tmpdir'
require 'scout/tmpfile'

class TestTmpFileWithFileCleanup < Test::Unit::TestCase
  def test_exception_leaves_temp_file_behind
    # with_file has no ensure around the yield: a raising block leaves
    # the temporary file in the tmpdir. Cleanup is the caller's job.
    Dir.mktmpdir do |d|
      TmpFile.tmpdir = d
      assert_raise { TmpFile.with_file('data') { |f| raise 'boom' if File.exist?(f) } }
      assert_equal 1, Dir.children(d).length, 'temp file left behind by raising block'
    end
  end

  def test_normal_exit_removes_file
    seen = nil
    TmpFile.with_file('data') do |file|
      seen = file
    end
    assert ! File.exist?(seen)
  end
end
