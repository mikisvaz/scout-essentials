module Misc

  def self.hostname
    @@hostname ||= begin
                     (ENV["HOSTNAME"] || `hostname`).strip
                   end
  end

  def self.children(ppid = nil)
    require 'sys/proctable'

    ppid ||= Process.pid
    Sys::ProcTable.ps.select{ |pe| pe.ppid == ppid }
  end

  def self.wait_child(pid)
    begin
      Process.waitpid2 pid.to_i
    rescue Errno::ECHILD
    end
  end

  def self.abort_child(pid, wait = true)
    begin
      Process.kill("TERM", pid.to_i)
      wait_child(pid) if wait
    rescue
      Log.debug("Process #{pid} was not killed: #{$!.message}")
    end
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

  def self.with_envs(hash, &block)
    old_value = {}
    begin
      hash.each do |var,value|
        old_value[var] = ENV[var]
        ENV[var] = value
      end
      yield
    ensure
      old_value.each do |var,value|
        ENV[var] = value
      end
    end
  end


  def self.update_git(gem_name = 'scout-essentials')
    gem_name = 'scout-essentials' if gem_name.nil?
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
