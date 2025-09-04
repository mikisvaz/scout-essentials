require_relative '../open'
require 'json'
require 'yaml'

module Open
  def self.json(file)
    file = file.find_with_extension :json if Path === file
    Open.open(file){|f| JSON.load(f) }
  end

  def self.yaml(file)
    file = file.find_with_extension :yaml if Path === file
    Open.open(file){|f| YAML.unsafe_load(f) }
  end

  def self.marshal(file)
    Open.open(file){|f| Marshal.load(f) }
  end
end
