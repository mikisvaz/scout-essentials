require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/resource'
require 'scout/resource/scout'

class TestResourceSoftware < Test::Unit::TestCase
  module TestResource
    extend Resource

    self.subdir = Path.setup('tmp/test-resource')
  end

  def test_install
    Resource.install nil, "scout_install_example", tmpdir.software do
      <<-EOF
echo "#!/bin/bash\necho WORKING" > $OPT_BIN_DIR/scout_install_example
chmod +x $OPT_BIN_DIR/scout_install_example
      EOF
    end
    assert_nothing_raised do
      CMD.cmd(tmpdir.software.opt.bin.scout_install_example).read
    end
    assert_equal "WORKING", CMD.cmd('scout_install_example').read.strip
  end
end

