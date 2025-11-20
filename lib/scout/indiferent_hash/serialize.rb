module IndiferentHash
  def self.serializable(obj)
	case obj
	when Hash
	  obj.each_with_object({}) do |(k, v), h|
		h[k] = serializable(v)
	  end

	when Array
	  if obj.length <= 100
		obj.map { |v| serializable(v) }
	  else
		first = obj.first(70).map { |v| serializable(v) }
		last  = obj.last(30).map { |v| serializable(v) }
		truncated_msg = "TRUNCATED only 100 out of #{obj.length} shown"

		first + ['...'] + last + [truncated_msg]
	  end

	else
	  obj
	end
  end
end
