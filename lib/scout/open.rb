require_relative 'path'
require_relative 'cmd'

require_relative 'open/final'
require_relative 'open/stream'
require_relative 'open/util'
require_relative 'open/remote'
require_relative 'open/lock'
require_relative 'open/sync'

module Open
  module NamedStream
    attr_accessor :filename

    def digest_str
      if Path === filename && ! filename.located?
        filename
      else
        Misc.file_md5(filename)
      end
    end
  end

  def self.file_open(file, grep = false, mode = 'r', invert_grep = false, fixed_grep = true, options = {})
    Open.mkdir File.dirname(file) if mode.include? 'w'

    stream = get_stream(file, mode, options)

    if grep
      grep(stream, grep, invert_grep, fixed_grep)
    else
      stream
    end
  end

  def self.open(file, options = {})
    if IO === file || StringIO === file
      if block_given?
        res = yield file, options
        file.close
        return res
      else
        return file
      end
    end

    options = IndiferentHash.add_defaults options, :noz => false, :mode => 'r'

    mode, grep, invert_grep, fixed_grep = IndiferentHash.process_options options, :mode, :grep, :invert_grep, :fixed_grep

    options[:noz] = true if mode.include? "w"

    io = file_open(file, grep, mode, invert_grep, fixed_grep, options)

    io = unzip(io)   if ((String === file and zip?(file))   and not options[:noz]) or options[:zip]
    io = gunzip(io)  if ((String === file and gzip?(file))  and not options[:noz]) or options[:gzip]
    io = bgunzip(io) if ((String === file and bgzip?(file)) and not options[:noz]) or options[:bgzip]

    io.extend NamedStream
    io.filename = file

    if block_given?
      res = nil
      begin
        res = yield(io)
      rescue DontClose
        res = $!.payload
      rescue Exception
        io.abort $! if io.respond_to? :abort
        io.join if io.respond_to? :join
        raise $!
      ensure
        io.close if io.respond_to? :close and not io.closed?
        io.join if io.respond_to? :join
      end
      res
    else
      io
    end
  end

  def self.read(file, options = {}, &block)
    open(file, options) do |f|
      if block_given?
        res = []
        while not f.eof?
          l = f.gets
          l = Misc.fixutf8(l) unless options[:nofix]
          res << yield(l)
        end
        res
      else
        if options[:nofix]
          f.read
        else
          Misc.fixutf8(f.read)
        end
      end
    end
  end
end
