require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestPersistOpen < Test::Unit::TestCase

  def obj
    ["TEST", 2, :symbol, {"a" => [1,2], :b => 3}]
  end

  def test_json
    obj = ["TEST", 2]
    TmpFile.with_file(obj.to_json) do |tmpfile|
      assert_equal obj, Open.json(tmpfile)
    end
  end

  def test_yaml
    TmpFile.with_file(obj.to_yaml) do |tmpfile|
      assert_equal obj, Open.yaml(tmpfile)
    end
  end

  def test_marshal
    TmpFile.with_file(Marshal.dump(obj)) do |tmpfile|
      assert_equal obj, Open.marshal(tmpfile)
    end
  end

  def test_yaml_io
    TmpFile.with_file(obj.to_yaml) do |tmpfile|
      Open.open(tmpfile) do |f|
        assert_equal obj, Open.yaml(f)
      end
    end
  end
end

