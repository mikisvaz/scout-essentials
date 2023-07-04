require_relative '../log'
module SOPT

  class << self
    attr_writer :command, :summary, :synopsys, :description
  end

  def self.command
    @command ||= File.basename($0)
  end

  def self.summary
    @summary ||= ""
  end

  def self.synopsys
    @synopsys ||= begin
                    "#{command} " <<
                    inputs.collect{|name|
                      "[" << input_format(name, input_types[name] || :string, input_defaults[name], input_shortcuts[name]).sub(/:$/,'') << "]"
                    } * " "
                  end
  end

  def self.description
    @description ||= "Missing"
  end

  def self.input_format(name, type = nil, default = nil, short = nil)
    input_str = (short.nil? or short.empty?) ? "--#{name}" : "-#{short},--#{name}"
    input_str = Log.color(:blue, input_str)
    extra = case type
    when nil
      ""
    when :boolean
      "[=false]" 
    when :tsv, :text
      "=<file|->"
    when :array
      "=<list|file|->"
    else
      "=<#{ type }>"
    end
    #extra << " (default: #{Array === default ? (default.length > 3 ? default[0..2]*", " + ', ...' : default*", " ): default})" if default != nil
    extra << " (default: #{Log.fingerprint(default)})" if default != nil
    input_str << Log.color(:green, extra)
  end

  def self.input_array_doc(input_array)
    input_array.collect do |name,type,description,default,options|
      type = :string if type.nil?

      name = name.to_s
      shortcut, options = options, nil if String === options || Symbol === options

      case options && options[:shortcut]
      when FalseClass
        shortcut = nil
      when TrueClass, nil
        shortcut = fix_shortcut(name[0], name)
      else
        shortcut = options[:shortcut]
      end unless shortcut

      shortcut = fix_shortcut(shortcut, name)
      register(shortcut, name, type, description) unless self.inputs.include? name
      name  = SOPT.input_format(name, type.to_sym, default, shortcut ) 
      Misc.format_definition_list_item(name, description)
    end * "\n"
  end

  def self.input_doc(inputs, input_types = nil, input_descriptions = nil, input_defaults = nil, input_shortcuts = nil)
    type = description = default = nil
    shortcut = ""
    seen = []
    inputs.collect do |name|
      next if seen.include? name
      seen << name

      type = input_types[name] unless input_types.nil?
      description = input_descriptions[name] unless input_descriptions.nil?
      default = input_defaults[name] unless input_defaults.nil?

      name = name.to_s

      case input_shortcuts
      when nil, FalseClass
        shortcut = nil
      when Hash
        shortcut = input_shortcuts[name] 
      when TrueClass
        shortcut = fix_shortcut(name[0], name)
      end

      type = :string if type.nil?
      register(shortcut, name, type, description) unless self.inputs.include? name

      name  = SOPT.input_format(name, type.to_sym, default, shortcut) 
      Misc.format_definition_list_item(name, description)
    end * "\n"
  end


  def self.doc
    doc =<<-EOF
#{Log.color :magenta}#{command}(1) -- #{summary}
#{"=" * (command.length + summary.length + 7)}#{Log.color :reset}

    EOF

    if synopsys and not synopsys.empty?
      doc << Log.color(:magenta, "## SYNOPSYS") << "\n\n"
      doc << Log.color(:blue, synopsys) << "\n\n"
    end

    if description and not description.empty?
      doc << Log.color(:magenta, "## DESCRIPTION") << "\n\n"
      doc << Misc.format_paragraph(description) << "\n\n"
    end

    doc << Log.color(:magenta, "## OPTIONS") << "\n\n"
    doc << input_doc(inputs, input_types, input_descriptions, input_defaults, input_shortcuts)

    doc
  end
end
