require_relative '../misc/digest'
module Path
  def digest_str
    case
    when File.directory?(self)
      "Directory MD5: #{Misc.digest_str(self.glob("*"))}"
    when self.located? && File.exist?(self)
      "File MD5: #{Misc.digest_file(self)}"
    else
      '\'' << self << '\''
    end
  end
end
