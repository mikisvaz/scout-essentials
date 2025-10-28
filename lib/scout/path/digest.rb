require_relative '../misc/digest'
module Path
  def digest_str
    case
    when File.directory?(self)
      files = self.glob("*")

      files = files.reject{|f| File.directory?(f) }

      files = Annotation.purge files

      if files.length > 10
        "Directory MD5: #{files.length} #{Misc.digest_str(files*"\n")}"
      else
        "Directory MD5: #{Misc.digest_str(files)}"
      end
    when self.located? && File.exist?(self)
      "File MD5: #{Misc.digest_file(self)}"
    else
      '\'' + self << '\''
    end
  end
end
