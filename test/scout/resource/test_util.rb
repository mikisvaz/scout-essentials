require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/resource'
require 'scout/resource/scout'

class TestResourceUtil < Test::Unit::TestCase
  def test_identify
    path = Path.setup('share/data/somedir/somepath').find
    assert_equal 'share/data/somedir/somepath', Scout.identify(path)
  end

  def test_identify_dir
    path = Path.setup('share/data/somedir/').find
    assert_equal 'share/data/somedir', Scout.identify(path)
  end

  def test_identify_with_subdir
    m = Module.new
    m.extend Resource
    m.subdir = 'test/subdir'
    path = m.root['share/data/somedir/somepath'].find
    assert_equal 'share/data/somedir/somepath', m.identify(path)
  end


  def test_relocate
    TmpFile.with_file do |dir|
      Path.setup dir

      path_base = Path.setup("basedir").someother.file
      path_base.path_maps[:subdir1] = File.join(dir, 'subdir1', '{PATH}')
      path_base.path_maps[:subdir2] = File.join(dir, 'subdir2', '{PATH}')

      path1 = path_base.find(:subdir1)
      path2 = path_base.find(:subdir2)

      Open.write(path1, "TEST")
      Open.mv path1, path2
      assert_equal path2, Resource.relocate(path1)
    end
  end

  def ___test_s3
    require 'scout-camp'
    require 'scout/aws/s3'
    p = Path.setup("s3://bucket/var/jobs/workflow/task/job.txt")
    p.path_maps = {:bucket => 's3://bucket/{TOPLEVEL}/{SUBPATH}'}

    assert_equal 'var/jobs/workflow/task/job.txt', Resource.identify(p)
  end
end

