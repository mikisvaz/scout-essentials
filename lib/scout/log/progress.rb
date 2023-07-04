require_relative 'progress/util'
require_relative 'progress/report'
module Log

  def self.no_bar=(value)
    @@no_bar = value
  end

  def self.no_bar
    @@no_bar = false unless defined?(@@no_bar)
    @@no_bar || ENV["SCOUT_NO_PROGRESS"] == "true"
  end

  class ProgressBar

    class << self
      attr_accessor :default_file
      attr_accessor :default_severity
    end

    attr_accessor :max, :ticks, :frequency, :depth, :desc, :file, :bytes, :process, :callback, :severity

    def initialize(max = nil, options = {})
      depth, desc, file, bytes, frequency, process, callback, severity = 
        IndiferentHash.process_options options, :depth, :desc, :file, :bytes, :frequency, :process, :callback, :severity,
        :depth => 0, :frequency => 2, :severity => Log::ProgressBar.default_severity

      max = nil if TrueClass === max

      @max = max
      @ticks = 0
      @frequency = frequency
      @severity = severity
      @last_time = nil
      @last_count = nil
      @last_percent = nil
      @depth = depth
      @desc = desc.nil? ? "" : desc.gsub(/\n/,' ')
      @file = file
      @bytes = bytes
      @process = process
      @callback = callback
    end

    def percent
      return 0 if @ticks == 0
      return 100 if @max == 0
      (@ticks * 100) / @max
    end

    def file
      @file || ProgressBar.default_file
    end

    def init
      @ticks, @bytes = 0
      @last_time = @last_count = @last_percent = nil
      @history, @mean_max, @max_history = nil
      @start = @last_time = Time.now
      @last_count = 0
      report
    end

    def tick(step = 1)
      return if Log.no_bar
      @ticks += step

      time = Time.now
      if @last_time.nil?
        @last_time = time
        @last_count = @ticks
        @start = time
        return
      end

      diff = time - @last_time
      report and return if diff >= @frequency
      return unless max and max > 0

      percent = self.percent
      if @last_percent.nil?
        @last_percent = percent
        return
      end
      report && return if percent > @last_percent and diff > 0.3
    end

    def pos(pos)
      step = pos - (@ticks || 0)
      tick(step)
    end

    def process(elem)
      case res = @process.call(elem)
      when FalseClass
        nil
      when TrueClass
        tick
      when Integer
        pos(res)
      when Float
        pos(res * max)
      end
    end
  end
end
