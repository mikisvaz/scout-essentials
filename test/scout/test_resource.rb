require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestResourceUnit < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource')
  end


  def test_root

    p = TestResource.root.some_file
    assert p.find(:user).include?(ENV["HOME"])
  end

  def __test_identify
    assert_equal 'etc/', Rbbt.identify(File.join(ENV["HOME"], '.rbbt/etc/'))
    assert_equal 'share/databases/', Rbbt.identify('/usr/local/share/rbbt/databases/')
    assert_equal 'share/databases/DATABASE', Rbbt.identify('/usr/local/share/rbbt/databases/DATABASE')
    assert_equal 'share/databases/DATABASE/FILE', Rbbt.identify('/usr/local/share/rbbt/databases/DATABASE/FILE')
    assert_equal 'share/databases/DATABASE/FILE', Rbbt.identify(File.join(ENV["HOME"], '.rbbt/share/databases/DATABASE/FILE'))
    assert_equal 'share/databases/DATABASE/FILE', Rbbt.identify('/usr/local/share/rbbt/databases/DATABASE/FILE')
  end
end
