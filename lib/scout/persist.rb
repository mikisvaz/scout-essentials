require_relative 'persist/serialize'
require_relative 'persist/open'
require_relative 'persist/path'

module Persist
  class << self
    attr :cache_dir
    def cache_dir=(cache_dir)
      @cache_dir = Path === cache_dir ? cache_dir : Path.setup(cache_dir)
    end
    def cache_dir
      @cache_dir ||= Path.setup("var/cache/persistence")
    end

    attr_writer :lock_dir
    def lock_dir
      @lock_dir ||= Path.setup("tmp/persist_locks").find
    end
  end

  def self.persistence_path(name, options = {})
    options = IndiferentHash.add_defaults options, :dir => Persist.cache_dir
    other_options = IndiferentHash.pull_keys options, :other
    name = name.filename if name.respond_to?(:filename) && name.filename
    persist_options = {}
    TmpFile.tmp_for_file(name, options.merge(persist_options), other_options)
  end

  MEMORY_CACHE = {}
  CONNECTIONS = {}
  def self.persist(name, type = :serializer, options = {}, &block)
    persist_options = IndiferentHash.pull_keys options, :persist 
    return yield if FalseClass === persist_options[:persist]
    file = persist_options[:path] || options[:path] || persistence_path(name, options)

    if type == :memory
      repo = options[:memory] || options[:repo] || MEMORY_CACHE
      repo[file] ||= yield
      return repo[file]
    end

    update = options[:update] || persist_options[:update]
    update = Open.mtime(update) if Path === update
    update = Open.mtime(file) >= update ? false : true if Time === update

    lockfile = persist_options[:lockfile] || options[:lockfile] || Persist.persistence_path(file + '.persist', {:dir => Persist.lock_dir})

    Open.lock lockfile do |lock|
      if Open.exist?(file) && ! update
        Persist.load(file, type)
      else
        begin
          file = file.find if Path === file
          return yield(file) if block.arity == 1
          res = yield

          if res.nil?
            return Persist.load(file, type)
          end

          Open.rm(file)

          if IO === res || StringIO === res
            tee_copies = options[:tee_copies] || 1
            main, *copies = Open.tee_stream_thread_multiple res, tee_copies + 1
            main.lock = lock
            t = Thread.new do
              Thread.current.report_on_exception = false
              Thread.current["name"] = "file saver: " + file
              Open.sensible_write(file, main)
            end
            Thread.pass until t["name"]
            copies.each_with_index do |copy,i|
              next_stream = copies[i+1] if copies.length > i
              ConcurrentStream.setup copy, :threads => t, :filename => file, :autojoin => true, :next => next_stream
            end
            res = copies.first
            raise KeepLocked.new(res)
          else
            pres = Persist.save(res, file, type)
            res = pres unless pres.nil?
          end
        rescue Exception
          Thread.handle_interrupt(Exception => :never) do
            if Open.exist?(file)
              Log.debug "Failed persistence #{file} - erasing"
              Open.rm file
            else
              Log.debug "Failed persistence #{file}"
            end
          end
          raise $! unless options[:canfail]
        end
        res
      end
    end
  end

  def self.memory(name, options = {}, &block)
    options[:persist_path] ||= options[:path] ||= [name, options[:key]].compact * ":"
    self.persist(name, :memory, options, &block)
  end

end
