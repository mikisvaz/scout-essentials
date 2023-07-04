module Misc

  def self.hostname
    @@hostname ||= begin
                     `hostname`.strip
                   end
  end

  def self.children(ppid = nil)
    require 'sys/proctable'

    ppid ||= Process.pid
    Sys::ProcTable.ps.select{ |pe| pe.ppid == ppid }
  end

  def self.env_add(var, value, sep = ":", prepend = true)
    if ENV[var].nil?
      ENV[var] = value
    elsif ENV[var] =~ /(#{sep}|^)#{Regexp.quote value}(#{sep}|$)/
      return
    else
      if prepend
        ENV[var] = value + sep + ENV[var]
      else
        ENV[var] += sep + value
      end
    end
  end

  def self.with_env(var, value, &block)
    old_value = ENV[var]
    begin
      ENV[var] = value
      yield
    ensure
      ENV[var] = old_value
    end
  end
  
  def self.update_git(gem_name = 'scout-gear')
    gem_name = 'scout-gear' if gem_name.nil?
    dir = File.join(__dir__, '../../../../', gem_name)
    return unless Open.exist?(dir)
    Misc.in_dir dir do
      begin
        begin
          CMD.cmd_log('git pull')
        rescue
          raise "Could not update #{gem_name}"
        end

        begin
          CMD.cmd_log('git submodule update')
        rescue
          raise "Could not update #{gem_name} submodules"
        end


        begin
          CMD.cmd_log('rake install')
        rescue
          raise "Could not install updated #{gem_name}"
        end
      rescue
        Log.warn $!.message
      end
    end
  end

  def self.processors
    Etc.nprocessors
  end
end
