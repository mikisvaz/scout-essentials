require_relative '../misc'
require_relative '../path'
require_relative '../cmd'

module Open
  class << self
    attr_accessor :remote_cache_dir
    
    def remote_cache_dir
      @remote_cache_dir ||= Path.setup("var/cache/open-remote/").find
    end
  end

  def self.remote?(file)
    !! (file =~ /^(?:https?|ftp|ssh):\/\//)
  end

  def self.ssh?(file)
    !! (file =~ /^ssh:\/\//)
  end

  def self.ssh(file, options = {})
    m = file.match(/ssh:\/\/([^:]+):(.*)/)
    server = m[1]
    file = m[2]
    if server == 'localhost'
      Open.open(file)
    else
      CMD.cmd("ssh '#{server}' cat '#{file}'", :pipe => true, :autojoin => true)
    end
  end

  LAST_TIME = {}
  def self.wait(lag, key = nil)
    time = Time.now

    if LAST_TIME[key] != nil && (time < LAST_TIME[key] + lag)
      sleep (LAST_TIME[key] + lag) - time
    end

    LAST_TIME[key] = Time.now
  end

  def self.wget(url, options = {})
    options = options[:wget_options] if options.include?(:wget_options)
    if ! (options[:force] || options[:nocache]) && cache_file = in_cache(url, options)
      return file_open(cache_file)
    end

    Log.low "WGET:\n -URL: #{ url }\n -OPTIONS: #{options.inspect}"
    options = IndiferentHash.add_defaults options, "--user-agent=" => 'rbbt', :pipe => true, :autojoin => true

    wait(options[:nice], options[:nice_key]) if options[:nice]
    options.delete(:nice)
    options.delete(:nice_key)

    pipe  = options.delete(:pipe)
    quiet = options.delete(:quiet)
    post  = options.delete(:post)
    cookies = options.delete(:cookies)
    nocache = options.delete(:nocache)

    options["--quiet"]     = quiet if options["--quiet"].nil?
    options["--post-data="] ||= post if post

    if cookies
      options["--save-cookies"] = cookies
      options["--load-cookies"] = cookies
      options["--keep-session-cookies"] = true
    end

    stderr = case
             when options['stderr']
               options['stderr'] 
             when options['--quiet']
               false
             else
               nil
             end

    begin
      wget_options = options.dup
      wget_options = wget_options.merge( '-O' => '-') unless options.include?('--output-document')
      wget_options[:pipe] = pipe unless pipe.nil?
      wget_options[:stderr] = stderr unless stderr.nil?

      io = CMD.cmd("wget '#{ url }'", wget_options)
      if nocache && nocache.to_s != 'update'
        io
      else
        add_cache(url, io, options)
        open_cache(url, options)
      end
    rescue
     raise OpenURLError, "Error reading remote url: #{ url }.\n#{$!.message}"
    end
  end

  def self.download(url, file)
    begin
      CMD.cmd_log(:wget, "'#{url}' -O '#{file}'")
    rescue
      FileUtils.rm(file) if File.exist?(file)
      raise $!
    end
  end

  def self.digest_url(url, options = {})
    params = [url, options.values_at("--post-data", "--post-data="), (options.include?("--post-file")? Open.read(options["--post-file"]).split("\n").sort * "\n" : "")]
    Misc.digest([url, params])
  end

  def self.cache_file(url, options)
    File.join(self.remote_cache_dir, digest_url(url, options))
  end

  def self.in_cache(url, options = {})
    filename = cache_file(url, options)
    if File.exist? filename
      return filename 
    else
      nil
    end
  end

  def self.remove_from_cache(url, options = {})
    filename = cache_file(url, options)
    if File.exist? filename
      FileUtils.rm filename 
    else
      nil
    end
  end

  def self.add_cache(url, data, options = {})
    filename = cache_file(url, options)
    Open.sensible_write(filename, data, :force => true)
  end

  def self.open_cache(url, options = {})
    filename = cache_file(url, options)
    Open.open(filename)
  end

  def self.scp(source_file, target_file, target: nil, source: nil)
    CMD.cmd_log("ssh #{target} mkdir -p #{File.dirname(target_file)}")
    target_file = [target, target_file] * ":" if target && ! target_file.start_with?(target+":")
    source_file = [source, source_file] * ":" if source && ! source_file.start_with?(source+":")
    CMD.cmd_log("scp -r '#{ source_file }' #{target_file}")
  end
end
