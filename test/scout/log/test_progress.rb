require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestProgress < Test::Unit::TestCase
  SLEEP_TIME=0.0001
  def test_bar
    t1 = Thread.new do
      Log::ProgressBar.with_bar(20, :desc => "Bar 1") do |bar|
        20.times do
          bar.tick
          sleep SLEEP_TIME
        end
        Log.debug "Done progress"
        assert_equal 100, bar.percent
      end
    end

    t2 = Thread.new do
      Log::ProgressBar.with_bar(20, :desc => "Bar 2") do |bar|
        20.times do
          bar.tick
          sleep SLEEP_TIME
        end
        Log.debug "Done progress"
        assert_equal 100, bar.percent
      end
    end
    t1.join
    t2.join
  end

  def test_bar_no_size
    t1 = Thread.new do
      Log::ProgressBar.with_bar(nil, :desc => "Bar 1", :frequency => 0) do |bar|
        20.times do
          bar.tick
          sleep SLEEP_TIME
        end
        assert bar.history.length > 0
      end
    end

    t2 = Thread.new do
      Log::ProgressBar.with_bar(nil, :desc => "Bar 2", :frequency => 0) do |bar|
        20.times do
          bar.tick
          sleep SLEEP_TIME
        end
        assert bar.history.length > 0
      end
    end
    t1.join
    t2.join
  end

  def test_bar_nested
    Log::ProgressBar.with_bar(20, :desc => "Bar 1") do |bar|
      bar.init
      20.times do
        Log::ProgressBar.with_bar(5, :desc => "Bar 2") do |bar|
          5.times do
            bar.tick
            sleep SLEEP_TIME
          end
        end
        bar.tick
        sleep SLEEP_TIME
      end
    end
  end

  def test_pos
    size = 10000

    Log::ProgressBar.with_bar(size, :desc => "Bar 1") do |bar|
      bar.init
      nums = []
      100.times do
        nums << rand(size)
      end
      nums.sort.each do |num|
        bar.pos num
        sleep SLEEP_TIME
      end
      bar.tick
    end
  end

  def test_file
    size = 10000

    TmpFile.with_file do |file|

      Log::ProgressBar.with_bar(size, :desc => "Bar 1", :file => file) do |bar|
        bar.init
        nums = []
        100.times do
          nums << rand(size)
        end
        nums.sort.each do |num|
          bar.pos num
          sleep SLEEP_TIME
        end
        bar.tick
      end
    end
  end
end
