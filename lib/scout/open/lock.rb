require_relative '../path'
require_relative '../log'
require_relative '../exceptions'
require_relative 'lock/lockfile'

module Open
  def self.init_lock
    Lockfile.refresh = 2 
    Lockfile.max_age = 30
    Lockfile.suspend = 4
  end

  self.init_lock 

  def self.lock(file, unlock = true, options = {})
    unlock, options = true, unlock if Hash === unlock
    return yield if file.nil? and not Lockfile === options[:lock]

    if Lockfile === file
      lockfile = file
    else
      file = file.find if Path === file
      FileUtils.mkdir_p File.dirname(File.expand_path(file)) unless File.exist? File.dirname(File.expand_path(file))

      case options[:lock]
      when Lockfile
        lockfile = options[:lock]
      when FalseClass
        lockfile = nil
        unlock = false
      when Path, String
        lock_path = options[:lock].find
        lockfile = Lockfile.new(lock_path, options)
      else
        lock_path = File.expand_path(file + '.lock')
        lockfile = Lockfile.new(lock_path, options)
      end
    end

    begin
      lockfile.lock unless lockfile.nil? || lockfile.locked?
    rescue Aborted, Interrupt
      raise LockInterrupted
    end

    res = nil

    begin
      res = yield lockfile
    rescue KeepLocked
      unlock = false
      res = $!.payload
    ensure
      if unlock 
        begin
          if lockfile.locked?
            lockfile.unlock 
          end
        rescue Exception
          Log.warn "Exception unlocking: #{lockfile.path}"
          Log.exception $!
        end
      end
    end

    res
  end
end
