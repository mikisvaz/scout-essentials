module TmpFile
  def self.with_path(*args, &block)
    TmpFile.with_file(*args) do |file|
      Path.setup(file)
      yield file
    end
  end
end
