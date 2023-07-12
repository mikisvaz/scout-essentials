module Misc
  MAX_ARRAY_DIGEST_LENGTH = 100_000
  def self.digest_str(obj)
    if obj.respond_to?(:digest_str)
      obj.digest_str
    else
      case obj
      when String
        #'\'' << obj << '\''
        if Path === obj || ! Open.exists?(obj)
          '\'' << obj << '\''
        elsif File.directory?(obj)
          "Directory MD5: #{digest_str(Dir.glob(File.join(obj, "*")))}"
        else
          "File MD5: #{Misc.file_md5(obj)}"
        end
      when Integer, Symbol
        obj.to_s
      when Array
        if obj.length > MAX_ARRAY_DIGEST_LENGTH
          length = obj.length
          mid = length/2
          sample_pos = [1, 2, mid, length-2, length-1]
          "[#{length}:" << obj.values_at(*sample_pos).inject(""){|acc,o| acc.empty? ? Misc.digest_str(o) : acc << ', ' << Misc.digest_str(o) } << ']'
        else
          '[' << obj.inject(""){|acc,o| acc.empty? ? Misc.digest_str(o) : acc << ', ' << Misc.digest_str(o) } << ']'
        end
      when Hash
        '{' << obj.inject(""){|acc,p| s = Misc.digest_str(p.first) << "=" << Misc.digest_str(p.last); acc.empty? ? s : acc << ', ' << s } << '}'
      when Integer
        obj.to_s
      when Float
        if obj % 1 == 0
          obj.to_i.to_s
        elsif obj.abs > 10
          "%.1f" % obj
        elsif obj.abs > 1
          "%.3f" % obj
        else
          "%.6f" % obj
        end
      when TrueClass
        "true"
      when FalseClass
        "false"
      else
        obj.inspect
      end
    end
  end

  def self.digest(obj)
    str = String === obj ? obj : Misc.digest_str(obj)
    Digest::MD5.hexdigest(str)
  end

  def self.file_md5(file)
    file = file.find if Path === file
    file = File.expand_path(file)
    #md5file = file + '.md5'
    Persist.persist("MD5:#{file}", :string) do
      Digest::MD5.file(file).hexdigest
    end
  end
end
