require_relative '../../exceptions'
module Log
  class ProgressBar
    BAR_MUTEX = Mutex.new
    BARS = []
    REMOVE = []
    SILENCED = []

    def self.add_offset(value = 1)
      value = 1 if TrueClass === value
      @@offset = offset + value.to_i
      @@offset = 0 if @@offset < 0
      @@offset
    end

    def self.remove_offset(value = 1)
      value = 1 if TrueClass === value
      @@offset = offset - value.to_i
      @@offset = 0 if @@offset < 0
      @@offset
    end


    def self.offset
      @@offset ||= 0
      @@offset = 0 if @@offset < 0
      @@offset
    end

    def self.new_bar(max, options = {})
      options, max = max, nil if Hash === max
      max = options[:max] if options && max.nil?
      cleanup_bars
      BAR_MUTEX.synchronize do
        Log::LAST.replace "new_bar" if Log::LAST == "progress"
        options = IndiferentHash.add_defaults options, :depth => BARS.length + Log::ProgressBar.offset
        BARS << (bar = ProgressBar.new(max, options))
        bar
      end
    end

    def self.cleanup_bars
      BAR_MUTEX.synchronize do
        REMOVE.each do |bar|
          index = BARS.index bar
          if index
            BARS.delete_at index
            BARS.each_with_index do |bar,i|
              bar.depth = i
            end
          end
          index = SILENCED.index bar
          if index
            SILENCED.delete_at index
            SILENCED.each_with_index do |bar,i|
              bar.depth = i
            end
          end
        end
        REMOVE.clear
        BARS.length
      end
    end

    def self.remove_bar(bar, error = false)
      BAR_MUTEX.synchronize do
        return if REMOVE.include? bar
      end
      if error
        bar.error if bar.respond_to? :error
      else
        bar.done if bar.respond_to? :done
      end
      BAR_MUTEX.synchronize do
        REMOVE << bar
      end
      cleanup_bars
      Log::LAST.replace "remove_bar" if Log::LAST == "progress"
    end

    def remove(error = false)
      Log::ProgressBar.remove_bar self, error
    end

    def self.with_bar(max = nil, options = {})
      bar = options.include?(:bar) ? options[:bar] : new_bar(max, options)
      begin
        error = false
        keep = false
        yield bar
      rescue KeepBar
        keep = true
      rescue
        error = true
        raise $!
      ensure
        remove_bar(bar, error) if bar && ! keep
      end
    end

    def self.guess_obj_max(obj)
      begin
        case obj
        when (defined? Step and Step)
          if obj.done?
            path = obj.path
            path = path.find if path.respond_to? :find
            if File.exist? path
              CMD.cmd("wc -l '#{path}'").read.to_i 
            else
              nil
            end
          else
            nil
          end
        when TSV
          obj.length
        when Array, Hash
          obj.size
        when File
          return nil if Open.gzip?(obj.filename) or Open.bgzip?(obj.filename) or Open.remote?(obj.filename)
          CMD.cmd("wc -l '#{obj.filename}'").read.to_i
        when Path, String
          obj = obj.find if Path === obj
          if File.exist? obj
            return nil if Open.gzip?(obj) or Open.bgzip?(obj)
            CMD.cmd("wc -l '#{obj}'").read.to_i
          else
            nil
          end
        end
      rescue Interrupt
        raise $!
      rescue Exception
        nil
      end
    end

    def self.get_obj_bar(obj, bar = nil)
      return nil if bar.nil? || bar == false
      case bar
      when String
        max = guess_obj_max(obj)
        Log::ProgressBar.new_bar(max, {:desc => bar}) 
      when TrueClass
        max = guess_obj_max(obj)
        Log::ProgressBar.new_bar(max) 
      when Numeric
        max = guess_obj_max(obj)
        Log::ProgressBar.new_bar(bar) 
      when Hash
        max = IndiferentHash.process_options(bar, :max) || max
        Log::ProgressBar.new_bar(max, bar) 
      when Log::ProgressBar
        bar.max ||= guess_obj_max(obj)
        bar
      else
        if (defined? Step and Step === bar)
          max = guess_obj_max(obj)
          Log::ProgressBar.new_bar(max, {:desc => bar.status, :file => bar.file(:progress)}) 
        else
          bar
        end
      end
    end

    def self.with_obj_bar(obj, bar = true, &block)
      bar = get_obj_bar(obj, bar)
      with_bar nil, bar: bar, &block
    end
  end
end

