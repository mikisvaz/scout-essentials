require 'digest/md5'
module Log
  def self.fingerprint(obj)
    return obj.fingerprint if obj.respond_to?(:fingerprint)

    case obj
    when nil
      "nil"
    when TrueClass
      "true"
    when FalseClass
      "false"
    when Symbol
      ":" << obj.to_s
    when String
      if obj.length > 100
        digest = Digest::MD5.hexdigest(obj)
        "'" << obj.slice(0,30) << "<...#{obj.length} - #{digest[0..4]}...>" << obj.slice(-10,30)<< "'"
      else 
        "'" << obj << "'"
      end
    when ConcurrentStream
      name = obj.inspect + " " + obj.object_id.to_s
      name += " #{obj.filename}" if obj.filename
      name
    when IO
      (obj.respond_to?(:filename) and obj.filename ) ? "<IO:" + (obj.filename || obj.inspect + rand(100000)) + ">" : obj.inspect + " " + obj.object_id.to_s
    when File
      "<File:" + obj.path + ">"
    when Array
      if (length = obj.length) > 10
        "[#{length}--" <<  (obj.values_at(0,1, length / 2, -2, -1).collect{|e| fingerprint(e)} * ",") << "]"
      else
        "[" << (obj.collect{|e| fingerprint(e) } * ", ") << "]"
      end
    when Hash
      if obj.length > 10
        "H:{"<< fingerprint(obj.keys) << ";" << fingerprint(obj.values) << "}"
      else
        new = "{"
        obj.each do |k,v|
          new << fingerprint(k) << '=>' << fingerprint(v) << ' '
        end
        if new.length > 1
           new[-1] =  "}"
        else
          new << '}'
        end
        new
      end
    when Float
      if obj.abs > 10
        "%.1f" % obj
      elsif obj.abs > 1
        "%.3f" % obj
      else
        "%.6f" % obj
      end
    when Thread
      if obj["name"]
        obj["name"]
      else
        obj.inspect
      end
    else
      obj.to_s
    end
  end
end
