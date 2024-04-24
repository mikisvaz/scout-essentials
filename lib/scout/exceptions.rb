class ScoutDeprecated < StandardError; end
class ScoutException < StandardError; end

class FieldNotFoundError < StandardError;end

class TryAgain < StandardError; end
class StopInsist < Exception
  attr_accessor :exception
  def initialize(exception)
    @exception = exception
  end
end

class Aborted < StandardError; end

class ParameterException < ScoutException; end
class MissingParameterException < ParameterException
  def initialize(parameter)
    super("Missing parameter '#{parameter}'")
  end
end
class ProcessFailed < StandardError; 
  attr_accessor :pid, :msg
  def initialize(pid = Process.pid, msg = nil)
    @pid = pid
    @msg = msg
    if @pid
      if @msg
        message = "Process #{@pid} failed - #{@msg}"
      else
        message = "Process #{@pid} failed"
      end
    else
      message = "Failed to run #{@msg}"
    end
    super(message)
  end
end

class ConcurrentStreamProcessFailed < ProcessFailed
  attr_accessor :concurrent_stream
  def initialize(pid = Process.pid, msg = nil, concurrent_stream = nil)
    super(pid, msg)
    @concurrent_stream = concurrent_stream
  end
end

class OpenURLError < StandardError; end

class DontClose < Exception
  attr_accessor :payload
  def initialize(payload = nil)
    @payload = payload
  end
end

class DontPersist < Exception; end

class KeepLocked < DontPersist
  attr_accessor :payload
  def initialize(payload)
    @payload = payload
  end
end

class KeepBar < Exception
  attr_accessor :payload
  def initialize(payload)
    @payload = payload
  end
end

class LockInterrupted < TryAgain; end

class ClosedStream < StandardError; end

class ResourceNotFound < ScoutException; end

