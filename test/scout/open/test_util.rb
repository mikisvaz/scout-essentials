require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/open'

class TestOpenUtil < Test::Unit::TestCase
  def test_read_grep
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => '^1\|3') do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end

    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => ["1","3"]) do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end
  end

  def test_read_grep_invert
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => '^1\|3', :invert_grep => true) do |line| sum += line.to_i end
      assert_equal(2 + 4, sum)
    end

    TmpFile.with_file(content) do |file|
      sum = 0
      Open.read(file, :grep => ["1","3"]) do |line| sum += line.to_i end
      assert_equal(1 + 3, sum)
    end
  end

  def test_ln_s
    TmpFile.with_file do |directory|
      Path.setup(directory)
      file1 = directory.subdir1.file
      file2 = directory.subdir2.file
      Open.write(file1, "TEST")
      Open.ln_s file1, file2
      assert_equal "TEST", Open.read(file2)
      Open.write(file1, "TEST2")
      assert_equal "TEST2", Open.read(file2)
    end
  end

  def test_ln_h
    TmpFile.with_file do |directory|
      Path.setup(directory)
      file1 = directory.subdir1.file
      file2 = directory.subdir2.file
      Open.write(file1, "TEST")
      Open.ln_h file1, file2
      assert_equal "TEST", Open.read(file2)
      Open.write(file1, "TEST2")
      assert_equal "TEST2", Open.read(file2)
      assert_equal File.stat(file1).ino, File.stat(file2).ino
    end
  end

  def test_ln_recursive
    TmpFile.with_file do |directory|
      Path.setup(directory)
      file1 = directory.subdir1.file
      file2 = directory.subdir2.file
      Open.write(file1, "TEST")
      Open.link_dir directory.subdir1, directory.subdir2
      assert_equal "TEST", Open.read(file2)
      Open.write(file1, "TEST2")
      assert_equal "TEST2", Open.read(file2)
      assert_equal File.stat(file1).ino, File.stat(file2).ino
    end
  end
end

