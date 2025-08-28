require_relative 'path'
require_relative 'resource'
require_relative 'resource/scout'

module Scout::Config

  CACHE ||= IndiferentHash.setup({})

  GOT_KEYS=[]

  def self.add_entry(key, value, tokens)
    tokens = [tokens] unless Array === tokens
    tokens << "key:#{key}" unless tokens.include?("key:#{key}")
    CACHE[key.to_s] ||= [] 
    CACHE[key.to_s] << [tokens, value]
  end

  def self.load_file(file)
    Log.debug "Loading config file: #{ file }"
    Open.read(file).split("\n").each do |line|
      next if line =~ /^#/
      key, value, *tokens = line.strip.split(/\s+/)

      self.add_entry(key, value, tokens) if key
    end
  end

  def self.load_config
    Path.setup("etc").config.find_all.reverse.each do |file|
      self.load_file(file)
    end
  end

  def self.set(values, *tokens)
    if not Hash === values
      values = {values => tokens.shift}
    end

    values.each do |key,value|
      add_entry key, value, tokens
    end
  end

  def self.token_priority(token)
    token, _sep, priority = token.to_s.partition("::")

    if priority.nil? || priority.empty?
      type, _sep, rest = token.partition(":")
      priority = case type
                 when "workflow"
                   4
                 when "task"
                   3
                 when "file"
                   2
                 when "line"
                   1
                 when "key"
                   20
                 else
                   10
                 end
    else
      priority = priority.to_i
    end

    [token, priority]
  end

  def self.match(entries, give_token)
    priorities = {}
    entries.each do |tokens, value|
      best_prio = nil
      tokens = [tokens] unless Array === tokens
      tokens.each do |tok|
        tok, prio = token_priority tok
        next unless tok == give_token

        best_prio = prio if best_prio.nil? or best_prio > prio
        next if prio > best_prio

        priorities[prio] ||= []
        priorities[prio].unshift value
      end
    end if entries
    priorities
  end

  # For equal priorities the matching prioritizes tokens ealier in the list
  def self.get(key, *tokens)
    options = tokens.pop if Hash === tokens.last
    options = IndiferentHash.setup options if options

    default = options.nil? ? nil : options[:default]
    env = options.nil? ? nil : options[:env]

    if env
      env.split(/,\s*/).each do |variable|
        if ENV[variable]
          default = ENV[variable]
          break
        end
      end
    end

    tokens = ["key:" + key] if tokens.empty?

    tokens = tokens.flatten
    file, _sep, line = caller.reject{|l| 
      l =~ /rbbt\/(?:resource\.rb|workflow\.rb)/ or
        l =~ /rbbt\/resource\/path\.rb/ or
        l =~ /rbbt\/util\/misc\.rb/ or
        l =~ /accessor\.rb/ or
        l =~ /progress-monitor\.rb/ 
    }.first.partition(":")

    File.expand_path(file)

    tokens << ("file:" + file)
    tokens << ("line:" + file << ":" << line.sub(/:in \`.*/,''))

    entries = CACHE[key.to_s]
    priorities = {}
    tokens.each do |token|
      token_prio = match entries, token.to_s
      token_prio.each do |prio, values|
        priorities[prio] ||= []
        priorities[prio].concat(values)
      end
    end

    value = priorities.empty? ? default : priorities.collect{|p| p }.sort_by{|p,v| p}.first.last.first
    value = false if value == 'false'

    Log.debug "Value #{value.inspect} for config key '#{ key }': #{tokens * ", "}" + (env ? " env:#{env}" : '')
    GOT_KEYS << [key, value, tokens]

    if String === value && m = value.match(/^env:(.*)/)
      variables = m.captures.first
      variables.split(/,\s*/).each do |variable|
        value = ENV[variable]
        return value if value
      end
      nil
    elsif value == 'nil'
      nil
    else
      value
    end
  end

  def self.with_config
      saved_config = {}
      CACHE.each do |k,v|
        saved_config[k] = v.dup
      end
      saved_got_keys = GOT_KEYS.dup
    begin
      yield
    ensure
      CACHE.replace(saved_config)
      GOT_KEYS.replace(saved_got_keys)
    end
  end

  def self.process_config(config)
    if Path.is_filename?(config) && File.exist?(config)
      Scout::Config.load_file(config)
    elsif Scout.etc.config_profile[config].exists?
      Scout::Config.load_file(Scout.etc.config_profile[config].find)
    else
      key, value, *tokens = config.split(/\s/)
      tokens = tokens.collect do |tok|
        tok, _sep, prio = tok.partition("::")
        prio = "0" if prio.nil? or prio.empty?
        [tok, prio] * "::"
      end
      Scout::Config.set({key => value}, *tokens)
    end
  end


  self.load_config
end
