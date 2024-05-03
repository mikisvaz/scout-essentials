require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/resource/scout'
class TestResourceUnit < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource')
  end

  def test_root

    p = TestResource.root.some_file
    assert p.find(:user).include?(ENV["HOME"])
  end

  def test_identify
    assert_equal 'etc', Scout.identify(File.join(ENV["HOME"], '.scout/etc'))
    assert_equal 'share/databases', Resource.identify('/usr/local/share/scout/databases/')
    assert_equal 'share/databases/DATABASE', Resource.identify('/usr/local/share/scout/databases/DATABASE')
    assert_equal 'share/databases/DATABASE/FILE', Resource.identify('/usr/local/share/scout/databases/DATABASE/FILE')
    assert_equal 'share/databases/DATABASE/FILE', Resource.identify(File.join(ENV["HOME"], '.scout/share/databases/DATABASE/FILE'))
    assert_equal 'share/databases/DATABASE/FILE', Resource.identify('/usr/local/share/scout/databases/DATABASE/FILE')
  end
end
