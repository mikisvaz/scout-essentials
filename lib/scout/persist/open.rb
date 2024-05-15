require_relative '../open'
require 'json'
require 'yaml'

module Open
  def self.json(file)
    Open.open(file){|f| JSON.load(f) }
  end

  def self.yaml(file)
    Open.open(file){|f| YAML.unsafe_load(f) }
  end

  def self.marshal(file)
    Open.open(file){|f| Marshal.load(f) }
  end
end
