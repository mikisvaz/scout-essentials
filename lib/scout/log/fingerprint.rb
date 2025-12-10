require 'digest/md5'
module Log
  FP_MAX_STRING = 150
  FP_MAX_ARRAY = 20
  FP_MAX_HASH = 10
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
      ":" + obj.to_s
    when String
      if obj.length > FP_MAX_STRING
        digest = Digest::MD5.hexdigest(obj)
        middle = "<...#{obj.length} - #{digest[0..4]}...>"
        s = (FP_MAX_STRING - middle.length) / 2
        "'" + obj.slice(0,s-1) + middle + obj.slice(-s, obj.length ) + "'"
      else 
        "'" + obj + "'"
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
      if (length = obj.length) > FP_MAX_ARRAY
        "[#{length}--" + (obj.values_at(0,1, length / 2, -2, -1).collect{|e| fingerprint(e)} * ",") + "]"
      else
        "[" + (obj.collect{|e| fingerprint(e) } * ", ") + "]"
      end
    when Hash
      if obj.length > FP_MAX_HASH
        "H:{" + fingerprint(obj.keys) + ";" + fingerprint(obj.values) + "}"
      else
        new = "{"
        obj.each do |k,v|
          new += fingerprint(k) + '=>' + fingerprint(v) + ' '
        end
        if new.length > 1
           new[-1] =  "}"
        else
          new += '}'
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
    when Set
      fingerprint(obj.to_a)
    else
      obj.to_s
    end
  end
end
