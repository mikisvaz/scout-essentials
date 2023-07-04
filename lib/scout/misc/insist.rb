module Misc
  def self.insist(times = 4, sleep = nil, msg = nil)
    sleep_array = nil

    try = 0
    begin
      begin
        yield
      rescue Exception
        if Array === times
          sleep_array = times
          times = sleep_array.length
          sleep = sleep_array.shift
        end

        if sleep.nil?
          sleep_array = ([0] + [0.001, 0.01, 0.1, 0.5] * (times / 3)).sort[0..times-1]
          sleep = sleep_array.shift
        end
        raise $!
      end
    rescue TryAgain
      sleep sleep
      retry
    rescue StopInsist
      raise $!.exception
    rescue Aborted, Interrupt
      if msg
        Log.warn("Not Insisting after Aborted: #{$!.message} -- #{msg}")
      else
        Log.warn("Not Insisting after Aborted: #{$!.message}")
      end
      raise $!
    rescue Exception
      Log.exception $! if ENV["SCOUT_LOG_INSIST"] == 'true'
      if msg
        Log.warn("Insisting after exception: #{$!.class} #{$!.message} -- #{msg}")
      elsif FalseClass === msg
        nil
      else
        Log.warn("Insisting after exception:  #{$!.class} #{$!.message}")
      end

      if sleep and try > 0
        sleep sleep
        sleep = sleep_array.shift || sleep if sleep_array
      else
        Thread.pass
      end

      try += 1
      retry if try < times
      raise $!
    end
  end
end
