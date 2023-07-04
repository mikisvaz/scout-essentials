require_relative '../../misc'
require_relative '../../path'
require 'rake'

class Rake::FileTask
  class << self
    alias_method :old_define_task, :define_task
  end

  def self.define_task(file, *args, &block)
    @@files ||= []
    @@files << file
    old_define_task(file, *args, &block)
  end

  def self.files
    @@files
  end

  def self.clear_files
    @@files = []
  end
end

module ScoutRake
  class TaskNotFound < StandardError; end
  def self.run(rakefile, dir, task, &block)
    old_pwd = FileUtils.pwd

    Rake::Task.clear
    Rake::FileTask.clear_files

    t = nil
    pid = Process.fork{
      if block_given?
        TOPLEVEL_BINDING.receiver.instance_exec &block
      else
        if Path.is_filename? rakefile
          rakefile = rakefile.produce.find
          load rakefile
        else
          TmpFile.with_file(rakefile) do |tmpfile|
            load tmpfile
          end
        end
      end

      raise TaskNotFound if Rake::Task[task].nil?

      #Misc.pre_fork
      begin
        Misc.in_dir(dir) do
          Rake::Task[task].invoke

          Rake::Task.clear
          Rake::FileTask.clear_files
        end
      rescue Exception
        Log.error "Error in rake: #{$!.message}"
        Log.exception $!
        Kernel.exit! -1
      end
      Kernel.exit! 0
    }
    Process.waitpid(pid)
    raise "Rake failed" unless $?.success?

  end
end
