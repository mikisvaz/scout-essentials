require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

class TestOpen < Test::Unit::TestCase

  def test_read
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read file do |line| sum += line.to_i end
      assert_equal(1 + 2 + 3 + 4, sum)
      assert_equal(content, Open.read(file))
    end
  end

  def test_gzip
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      `gzip #{file}`
      assert_equal(content, Open.read(file + '.gz'))
      FileUtils.rm file + '.gz'
    end
  end



  #def test_wget
  #  assert(Misc.fixutf8(Open.wget('http://google.com', :quiet => true).read) =~ /html/)
  #end

  #def test_nice
  #  nice =  0.5

  #  t = Time.now
  #  Open.wget('http://google.com', :quiet => true, :nice => nice).read
  #  assert(Time.now - t + 0.5 >= nice)

  #  Open.wget('http://google.com', :quiet => true, :nice => nice, :nice_key => 1).read
  #  t = Time.now
  #  Open.wget('http://google.com', :quiet => true, :nice => nice, :nice_key => 1).read
  #  assert(Time.now - t + 0.5 >= nice)
  #end

  #def test_remote?
  #  assert(Open.remote?('http://google.com'))
  #  assert(! Open.remote?('~/.bashrc'))
  #end

  #def test_open
  #  assert(Open.read('http://google.com', :quiet => true, :nocache => :update) =~ /html/)
  #end

  #def test_repo_dir
  #  file1 = "TEST"
  #  file2 = "TEST" * 1000
  #  TmpFile.with_file do |tmpdir|
  #    tmpdir = Rbbt.tmp.repo_dir.find
  #    normal = File.join(tmpdir, 'normal')
  #    repo = File.join(tmpdir, 'repo')

  #    Open.repository_dirs.push(repo)

  #    Misc.benchmark(100) do
  #      filename = "file" << (rand * 100).to_i.to_s
  #      Open.write(File.join(normal, filename), file2)
  #      100.times do 
  #        Open.read(File.join(normal,  filename))
  #      end
  #    end

  #    Misc.benchmark(100) do
  #      filename = "file" << (rand * 100).to_i.to_s
  #      Open.write(File.join(repo, filename), file2)
  #      100.times do 
  #        Open.read(File.join(repo, filename))
  #      end
  #    end
  #  end
  #end
  #
  #def test_repo_dir2
  #  TmpFile.with_file do |tmpdir|
  #    tmpdir = Rbbt.tmp.repo_dir.find
  #    repo = File.join(tmpdir, 'repo')

  #    Open.repository_dirs.push(repo)

  #    obj = { :a => "???a"}
  #    filename = "file" << (rand * 100).to_i.to_s
  #    Open.write(File.join(repo, filename), Marshal.dump(obj))
  #    dump = Open.read(File.join(repo, filename))
  #    obj_cp = Marshal.load(dump)
  #    assert_equal obj, obj_cp
  #  end
  #end

  #def test_repo_marshal
  #  TmpFile.with_file do |tmpdir|
  #    tmpdir = Rbbt.tmp.repo_dir.find
  #    repo = File.join(tmpdir, 'repo')

  #    filename = 'file'
  #    Open.repository_dirs.push(repo)

  #    obj = {:a => "string", :pid => nil, :num => 1000, :p  => Rbbt.tmp.foo}
  #    Open.write(File.join(repo, filename), Marshal.dump(obj))
  #    new =Open.open(File.join(repo, filename)) do |f|
  #      Marshal.load(f)
  #    end

  #    assert_equal new, obj
  #  end

  #end

  #def test_write_stream_repo
  #  TmpFile.with_file do |tmpdir|
  #    tmpdir = Rbbt.tmp.repo_dir.find
  #    repo = File.join(tmpdir, 'repo')

  #    file = File.join(repo, 'file')
  #    Open.repository_dirs.push(repo)

  #    text = (["text"] * 5) * "\n"

  #    Misc.consume_stream(StringIO.new(text), false, file)

  #    assert_equal text, Open.read(file)
  #    assert !File.exist?(file)
  #    assert Open.exists? file
  #  end

  #end

end

