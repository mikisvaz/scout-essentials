module Resource

  def self.install_helpers
    File.expand_path(Scout.share.software.install_helpers.find(:lib))
  end

  def self.install(content, name, software_dir = Path.setup('software'), &block)
    software_dir ||= Path.setup('software')
    software_dir = software_dir.find(:user) if Path === software_dir

    content = block if block_given?

    preamble = <<-EOF
#!/bin/bash

SOFTWARE_DIR="#{software_dir}"

INSTALL_HELPER_FILE="#{install_helpers}"
source "$INSTALL_HELPER_FILE"
    EOF

    content = content.call if Proc === content

    name = content[:name] if Hash === content && content.include?(:name)
    content = 
      if content =~ /git:|\.git$/
        {:git => content}
      else
        {:src => content}
      end if String === content and Open.remote?(content)

      script_text = 
        case content
        when nil
          raise "No way to install #{name}"
        when Path
          Open.read(content) 
        when String
          if Path.is_filename?(content) and Open.exists?(content)
            Open.read(content) 
          else
            content
          end
        when Hash
          name = content[:name] || name
          git = content[:git]
          src = content[:src]
          url = content[:url]
          jar = content[:jar]
          extra = content[:extra]
          commands = content[:commands]
          if git
            <<-EOF

name='#{name}'
url='#{git}'

install_git "$name" "$url" #{extra}

#{commands}
            EOF
          elsif src
            <<-EOF

name='#{name}'
url='#{src}'

install_src "$name" "$url" #{extra}

#{commands}
            EOF
          elsif jar
            <<-EOF

name='#{name}'
url='#{jar}'

install_jar "$name" "$url" #{extra}

#{commands}
            EOF
          else
            <<-EOF

name='#{name}'
url='#{url}'

#{commands}
            EOF
          end
        end

      script = preamble + "\n" + script_text
      Log.debug "Installing software #{name} into #{software_dir} with script:\n" << script
      CMD.cmd_log('bash', :in => script)
      Resource.set_software_env(software_dir)
  end

  def self.set_software_env(software_dir = Path.setup('software'))
    software_dir.opt.find_all.collect{|d| d.annotate(File.dirname(d)) }.reverse.each do |software_dir|
      next unless software_dir.exists?
      Log.medium "Preparing software env at #{software_dir}"

      software_dir = File.expand_path(software_dir)
      opt_dir = File.join(software_dir, 'opt')
      bin_dir = File.join(opt_dir, 'bin')

      Misc.env_add 'PATH', bin_dir

      FileUtils.mkdir_p opt_dir unless File.exist? opt_dir

      %w(.ld-paths .c-paths .pkgconfig-paths .aclocal-paths .java-classpaths).each do |file|
        filename = File.join(opt_dir, file)
        begin
          FileUtils.touch filename unless File.exist? filename
        rescue
          Log.warn("Could not touch #{ filename }")
        end
      end

      Open.read(File.join opt_dir, '.c-paths').split(/\n/).each do |line|
        dir = line.chomp
        dir = File.join(opt_dir, dir) unless dir[0] == "/"
        Misc.env_add('CPLUS_INCLUDE_PATH',dir)
        Misc.env_add('C_INCLUDE_PATH',dir)
      end if File.exist? File.join(opt_dir, '.c-paths')

      Open.read(File.join opt_dir, '.ld-paths').split(/\n/).each do |line|
        dir = line.chomp
        dir = File.join(opt_dir, dir) unless dir[0] == "/"
        Misc.env_add('LIBRARY_PATH',dir)
        Misc.env_add('LD_LIBRARY_PATH',dir)
        Misc.env_add('LD_RUN_PATH',dir)
      end if File.exist? File.join(opt_dir, '.ld-paths')

      Open.read(File.join opt_dir, '.pkgconfig-paths').split(/\n/).each do |line|
        dir = line.chomp
        dir = File.join(opt_dir, dir) unless dir[0] == "/"
        Misc.env_add('PKG_CONFIG_PATH',dir)
      end if File.exist? File.join(opt_dir, '.pkgconfig-paths')

      Open.read(File.join opt_dir, '.aclocal-paths').split(/\n/).each do |line|
        dir = line.chomp
        dir = File.join(opt_dir, dir) unless dir[0] == "/"
        Misc.env_add('ACLOCAL_FLAGS', "-I #{dir}", ' ')
      end if File.exist? File.join(opt_dir, '.aclocal-paths')

      Open.read(File.join opt_dir, '.java-classpaths').split(/\n/).each do |line|
        dir = line.chomp
        dir = File.join(opt_dir, dir) unless dir[0] == "/"
        Misc.env_add('CLASSPATH', "#{dir}")
      end if File.exist? File.join(opt_dir, '.java-classpaths')

      Dir.glob(File.join opt_dir, 'jars', '*.jar').each do |file|
        Misc.env_add('CLASSPATH', "#{file}")
      end

      if File.exist?(File.join(opt_dir, '.post_install')) and File.directory?(File.join(opt_dir, '.post_install'))
        Dir.glob(File.join(opt_dir, '.post_install','*')).each do |file|

          # Load exports
          Open.read(file).split("\n").each do |line|
            next unless line =~ /^\s*export\s+([^=]+)=(.*)/
            var = $1.strip
            value = $2.strip
            value.sub!(/^['"]/,'')
            value.sub!(/['"]$/,'')
            value.gsub!(/\$[a-z_0-9]+/i){|var| ENV[var[1..-1]] }
            Log.debug "Set variable export from .post_install: #{Log.fingerprint [var,value]*"="}"
            ENV[var] = value
          end
        end
      end
    end
  end

  self.set_software_env
end
