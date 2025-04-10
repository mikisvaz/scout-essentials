module Open

  def self.rsync(source, target, options = {})
    excludes, files, hard_link, test, print, delete, source_server, target_server, other = IndiferentHash.process_options options,
      :excludes, :files, :hard_link, :test, :print, :delete, :source, :target, :other

    excludes ||= %w(.save .crap .source tmp filecache open-remote)
    excludes = excludes.split(/,\s*/) if excludes.is_a?(String) and not excludes.include?("--exclude")

    if File.directory?(source) || source.end_with?("/")
      source += "/" unless source.end_with? '/'
      target += "/" unless target.end_with? '/'
    end

    if source == target && ! (source_server || target_server)
      Log.warn "Asking to rsync local file with itself"
      return
    end

    if target_server
      target_uri = [target_server, "'" + target + "'"] * ":" 
    else
      target_uri = "'" + target + "'"
    end

    if source_server
      source_uri = [source_server, "'" + source + "'"] * ":" 
    else
      source_uri = "'" + source + "'"
    end


    if target_server
      CMD.cmd("ssh #{target_server} mkdir -p '#{File.dirname(target)}'")
    else
      Open.mkdir File.dirname(target)
    end


    Log.low "Migrating #{source} #{files.length} files to #{target} - #{Misc.fingerprint(files)}}" if files


    rsync_args = %w(-avztHP --copy-unsafe-links --omit-dir-times)
    rsync_args << "--link-dest '#{source}'" if hard_link && ! source_server
    rsync_args << excludes.collect{|s| "--exclude '#{s}'" } if excludes and excludes.any?
    rsync_args << "-nv" if test
    if files
      tmp_files = TmpFile.tmp_file 'rsync_files-'
      Open.write(tmp_files, files * "\n")
      rsync_args << "--files-from='#{tmp_files}'"
    end

    cmd = "rsync #{rsync_args * " "} #{source_uri} #{target_uri}"
    case other
    when String
      cmd << " " << other
    when Array
      cmd << " " << other * " "
    end
    cmd << " && rm -Rf #{source}" if delete && ! files

    if print
      cmd
    else
      CMD.cmd_log(cmd, :log => Log::HIGH)

      if delete && files
        remove_files = files.collect{|f| File.join(source, f) }
        dirs = remove_files.select{|f| File.directory? f }
        remove_files.each do |file|
          next if dirs.include? file
          Open.rm file
        end

        dirs.each do |dir|
          FileUtils.rmdir dir if Dir.glob(dir).empty?
        end
      end 
    end
  end

  def self.sync(...)
    rsync(...)
  end
end
