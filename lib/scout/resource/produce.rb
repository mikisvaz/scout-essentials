require_relative '../open'
require_relative '../tmpfile'
require_relative 'produce/rake'

module Resource
  def claim(path, type, content = nil, &block)
    if type == :rake
      @rake_dirs ||= {}
      @rake_dirs[path] = content || block
    else
      @resources ||= {}
      @resources[path] = [type, content || block]
    end
  end

  def rake_for(path)
    @rake_dirs ||= {}
    @rake_dirs.select{|dir, content|
      Misc.path_relative_to(dir, path)
    }.sort_by{|dir, content|
      dir.length
    }.last
  end

  def has_rake(path)
    !! rake_for(path)
  end

  def run_rake(path, rakefile, rake_dir)
    task = Misc.path_relative_to rake_dir, path
    rakefile = rakefile.produce if rakefile.respond_to? :produce
    rakefile = rakefile.find if rakefile.respond_to? :find

    rake_dir = rake_dir.find(:user) if rake_dir.respond_to? :find

    begin
      Thread.current["resource"] = self
      if Proc === rakefile
        ScoutRake.run(nil, rake_dir, task, &rakefile)
      else
        ScoutRake.run(rakefile, rake_dir, task)
      end
    rescue ScoutRake::TaskNotFound
      if rake_dir.nil? or rake_dir.empty? or rake_dir == "/" or rake_dir == "./"
        raise $! 
      end
      task = File.join(File.basename(rake_dir), task)
      rake_dir = File.dirname(rake_dir)
      retry
    end
  end

  def produce(path, force = false)
    case
    when (@resources && @resources.include?(path))
      type, content = @resources[path]
    when (Path === path && @resources && @resources.include?(path.original))
      type, content = @resources[path.original]
    when has_rake(path)
      type = :rake
      rake_dir, content = rake_for(path)
      rake_dir = Path.setup(rake_dir.dup, self.pkgdir, self)
    else
      if path !~ /\.(gz|bgz)$/
        begin
          produce(path.annotate(path + '.gz'), force)
        rescue ResourceNotFound
          begin
            produce(path.annotate(path + '.bgz'), force)
          rescue ResourceNotFound
            raise ResourceNotFound, "Resource is missing and does not seem to be claimed: #{ self } -- #{ path } "
          end
        end
      else
        raise ResourceNotFound, "Resource is missing and does not seem to be claimed: #{ self } -- #{ path } "
      end
    end

    if path.respond_to?(:find) 
      final_path = force ? path.find(:default) : path.find
    else
      final_path = path
    end

    if type and not File.exist?(final_path) or force
      Log.medium "Producing: (#{self.to_s}) #{ final_path }"
      lock_filename = TmpFile.tmp_for_file(final_path, :dir => lock_dir)

      Open.lock lock_filename do
        FileUtils.rm_rf final_path if force and File.exist? final_path

        if ! File.exist?(final_path) || force 

          begin
            case type
            when :string
              Open.sensible_write(final_path, content)
            when :csv
              raise "TSV/CSV Not implemented yet"
              #require 'rbbt/tsv/csv'
              #tsv = TSV.csv Open.open(content)
              #Open.sensible_write(final_path, tsv.to_s)
            when :url
              options = {}
              options[:noz] = true if Open.gzip?(final_path) || Open.bgzip?(final_path) || Open.zip?(final_path)
              Open.sensible_write(final_path, Open.open(content, options))
            when :proc
              data = case content.arity
                     when 0
                       content.call
                     when 1
                       content.call final_path
                     end
              case data
              when String, IO, StringIO
                Open.sensible_write(final_path, data) 
              when Array
                Open.sensible_write(final_path, data * "\n")
              when TSV
                Open.sensible_write(final_path, data.dumper_stream) 
              when TSV::Dumper
                Open.sensible_write(final_path, data.stream) 
              when nil
              else
                raise "Unkown object produced: #{Log.fingerprint data}"
              end
            when :rake
              run_rake(path, content, rake_dir)
            when :install
              software_dir = self.root.software
              name = File.basename(path)
              Resource.install(content, name, software_dir)
              set_software_env(software_dir)
            else
              raise "Could not produce #{ resource }. (#{ type }, #{ content })"
            end
          rescue
            FileUtils.rm_rf final_path if File.exist? final_path
            raise $!
          end
        end
      end
    end

    # After producing a file, make sure we recheck all locations, the file
    # might have appeared with '.gz' extension for instance
    path.instance_variable_set("@path", {})

    path
  end

end
