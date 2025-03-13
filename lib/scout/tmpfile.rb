require_relative 'open'
require_relative 'misc'
require_relative 'log'
require 'fileutils'

module TmpFile
  MAX_FILE_LENGTH = 150

  def self.user_tmp(subdir = nil)
    if subdir
      File.join(ENV["HOME"],"/tmp/scout", subdir)
    else
      File.join(ENV["HOME"],"/tmp/scout")
    end
  end

  def self.tmpdir=(tmpdir)
    @tmpdir = tmpdir
  end

  def self.tmpdir
    @tmpdir ||= self.user_tmp('tmpfiles')
  end

  # Creates a random file name, with the given suffix and a random number
  # up to +max+
  def self.random_name(prefix = 'tmp-', max = 1_000_000_000)
    n = rand(max)
    prefix + n.to_s
  end

  # Creates a random filename in the temporary directory
  def self.tmp_file(prefix = 'tmp-', max = 1_000_000_000, dir = nil)
    dir ||= TmpFile.tmpdir
    dir = dir.find if Path === dir
    File.join(dir, random_name(prefix, max))
  end

  def self.with_file(content = nil, erase = true, options = {})
    if content.is_a?(Hash)
      options = content
      content = nil
      erase = true
    end
    if erase.is_a?(Hash)
      options = erase
      erase = true
    end

    prefix = options[:prefix] || 'tmp-'
    tmpdir = options[:tmpdir] || TmpFile.tmpdir
    max = options[:max] || 1_000_000_000
    tmpfile = tmp_file prefix, max, tmpdir
    tmpfile += ".#{options[:extension]}" if options[:extension]

    Open.mkdir tmpdir
    if IO === content
      Open.open(tmpfile, mode: 'wb') do |f|
        begin
          while c = content.readpartial(1024)
            f << c
          end
        rescue EOFError
        end
      end
    elsif !content.nil?
      Open.write(tmpfile, content)
    end

    result = yield(tmpfile)

    Open.rm_rf tmpfile if Open.exist?(tmpfile) && erase

    result
  end

  def self.with_dir(erase = true, options = {})
    prefix = options[:prefix] || 'tmpdir-'
    tmpdir = tmp_file prefix

    Open.mkdir tmpdir

    result = yield(tmpdir)

    Open.rm_rf tmpdir if Open.exist?(tmpdir) && erase

    result
  end

  def self.in_dir(*args)
    with_dir(*args) do |dir|
      Misc.in_dir dir do
        yield dir
      end
    end
  end

  SLASH_REPLACE = '·'
  def self.tmp_for_file(file, tmp_options = {}, other_options = {})
    tmp_for_file, prefix, key, persistence_dir = IndiferentHash.process_options tmp_options, :file, :prefix, :key, :dir
    return tmp_for_file unless tmp_for_file.nil?

    if prefix.nil?
      perfile = file.to_s.sub(/\.b?gz$/,'')
    else
      perfile = prefix.to_s + ":" + file.to_s.sub(/\.b?gz$/,'')
    end

    perfile += "[#{ key }]" if key

    if other_options.include? :filters
      other_options[:filters].each do |match,value|
        perfile = perfile + "&F[#{match}=#{Misc.digest(value)}]"
      end
    end

    persistence_dir = TmpFile.tmpdir if persistence_dir.nil?
    Path.setup(persistence_dir) unless Path === persistence_dir

    filename = perfile.gsub(/\s/,'_').gsub('/', SLASH_REPLACE)
    clean_options = other_options.dup
    clean_options.delete :unnamed
    clean_options.delete "unnamed"

    filename = filename[0..MAX_FILE_LENGTH] << Misc.digest(filename[MAX_FILE_LENGTH+1..-1]) if filename.length > MAX_FILE_LENGTH + 10

    filename  += ":" << Misc.digest(clean_options) unless clean_options.empty?

    persistence_dir[filename]
  end
end
