require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestLog < Test::Unit::TestCase
  def test_get_level
    assert_equal 0, Log.get_level(:debug)
    assert_equal 1, Log.get_level(:low)
    assert_equal 1, Log.get_level("LOW")
    assert_equal 1, Log.get_level(1)
    assert_equal 0, Log.get_level(nil)
  end

  def test_color
    assert Log.color(:green, "green")
  end

  def test_iif
    TmpFile.with_file do |tmp|
      Log.logfile(tmp)
      iif :foo
      assert File.read(tmp).include? ":foo"
      assert File.read(tmp).include? "INFO"
    end
  end

  def test_tty_size
    assert Integer === Log.tty_size
  end

end


