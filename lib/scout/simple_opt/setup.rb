module SOPT

  def self.setup(str)
    parts = str.split(/\n\n+/)

    summary = parts.shift unless parts.first =~ /^\s*\$-/
    synopsys = parts.shift if parts.first =~ /^\s*\$/

    description = []
    while parts.first and parts.first !~ /^\s*-/
      description << parts.shift
    end
    description = description * "\n\n"

    options = parts.collect{|part| part.split("\n").select{|l| l=~ /^\s*-/ }  }.flatten.compact * "\n"

    synopsys.sub!(/^\$\s+/,'') if synopsys

    SOPT.summary = summary.strip if summary
    SOPT.synopsys = synopsys.strip if synopsys
    SOPT.description = description.strip if description
    SOPT.parse options  if options

    SOPT.consume
  end
end
