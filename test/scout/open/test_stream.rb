require File.expand_path(__FILE__).sub(%r(/test/.*), '/test/test_helper.rb')
require File.expand_path(__FILE__).sub(%r(.*/test/), '').sub(/test_(.*)\.rb/,'\1')

require 'scout/path'
require 'scout/open'

class TestOpenStream < Test::Unit::TestCase
  def test_stream
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      TmpFile.with_file do |target|
        f = File.open(file)
        Open.consume_stream(f, false, target)
        assert_equal content, File.open(target).read
      end
    end
  end

  def test_sensible_write
    content =<<-EOF
1
2
3
4
    EOF
    TmpFile.with_file(content) do |file|
      TmpFile.with_file do |target|
        f = File.open(file)
        Open.sensible_write(target, f)
        assert_equal content, File.open(target).read
      end
    end
  end

  def test_open_pipe
    sout = Open.open_pipe do |sin|
      10.times do |i|
        sin.puts "line #{i}"
      end
    end

    TmpFile.with_file do |tmp|
      Open.consume_stream(sout, false, tmp)
      assert_equal 10, Open.read(tmp).split("\n").length
    end
  end

  def test_open_pipe_and_close

    10000.times do
      sout = Open.open_pipe do |sin|
        sin.puts "hola"
      end
      sout.read
      sout.close
    end
  end


  def test_open_pipe_error
    sout = Open.open_pipe do |sin|
      10.times do |i|
        sin.puts "line #{i}"
      end
      raise ScoutException
    end

    TmpFile.with_file do |tmp|
      assert_raise ScoutException do
        Open.consume_stream(sout, false, tmp)
      end
    end
  end

  def test_tee_stream
    num = 2000
    sout = Open.open_pipe do |sin|
      num.times do |i|
        sin.puts "line #{i} - #{rand(100000).to_s * 100}"
      end
    end

    TmpFile.with_file do |tmp|
      Path.setup tmp

      s1, s2 = Open.tee_stream_thread sout

      t1 = Open.consume_stream(s1, true, tmp.file1)
      t2 = Open.consume_stream(s2, true, tmp.file2)
      t1.join
      t2.join
      assert_equal num, Open.read(tmp.file1).split("\n").length
      assert_equal num, Open.read(tmp.file2).split("\n").length
    end
  end

  def test_tee_stream_multiple
    num = 2000
    sout = Open.open_pipe do |sin|
      num.times do |i|
        sin.puts "line #{i} - #{rand(100000).to_s * 100}"
      end
    end

    TmpFile.with_file do |tmp|
      Path.setup tmp

      s1, s2, s3 = Open.tee_stream_thread_multiple sout, 3

      t1 = Open.consume_stream(s1, true, tmp.file1)
      t2 = Open.consume_stream(s2, true, tmp.file2)
      t3 = Open.consume_stream(s3, true, tmp.file3)
      t1.join
      t2.join
      t3.join
      assert_equal num, Open.read(tmp.file1).split("\n").length
      assert_equal num, Open.read(tmp.file2).split("\n").length
      assert_equal num, Open.read(tmp.file3).split("\n").length
    end
  end


  def test_tee_stream_source_error
    5.times do |i|
      num = 2000
      sout = Open.open_pipe do |sin|
        num.times do |i|
          sin.puts "line #{i} - #{rand(100000).to_s * 100}"
        end
        raise ScoutException
      end

      TmpFile.with_file do |tmp|
        Path.setup tmp

        s1, s2 = Open.tee_stream_thread sout

        t1 = Open.consume_stream(s1, true, tmp.file1)
        t2 = Open.consume_stream(s2, true, tmp.file2)
        assert_raise ScoutException do
          begin
            t1.join
            t2.join
          rescue 
            raise
          ensure
            [t1, t2].each do |t|
              begin
                t.join if t.alive?
              rescue ScoutException
              end
            end
          end
        end
        refute Open.exist?(tmp.file1)
        refute Open.exist?(tmp.file2)
      end
    end
  end

  def test_tee_stream_source_error_multiple
    5.times do |i|
      num = 2000
      sout = Open.open_pipe do |sin|
        num.times do |i|
          sin.puts "line #{i} - #{rand(100000).to_s * 100}"
        end
        raise ScoutException
      end

      TmpFile.with_file do |tmp|
        Path.setup tmp

        s1, s2, s3 = Open.tee_stream_thread_multiple sout, 3

        t1 = Open.consume_stream(s1, true, tmp.file1)
        t2 = Open.consume_stream(s2, true, tmp.file2)
        t3 = Open.consume_stream(s3, true, tmp.file3)
        assert_raise ScoutException do
          begin
            t1.join
            t2.join
            t3.join
          rescue 
            raise
          ensure
            [t1, t2, t2].each do |t|
              begin
                t.join if t.alive?
              rescue ScoutException
              end
            end
          end
        end
        refute Open.exist?(tmp.file1)
        refute Open.exist?(tmp.file2)
        refute Open.exist?(tmp.file3)
      end
    end
  end

  def test_tee_stream_save_error
    Log.with_severity 6 do
      50.times do |i|
        TmpFile.with_file do |tmp|
          Path.setup tmp
          assert_raise ScoutException do
            num = 2000
            begin
              sout = Open.open_pipe do |sin|
                num.times do |i|
                  sin.puts "line #{i} - #{rand(100000).to_s * 100}"
                end
              end

              begin
                s1, s2 = Open.tee_stream_thread sout

                s2.abort ScoutException.new
                t = Open.consume_stream(s1, true, tmp.file)

                t.join
              ensure
                s1.close if s1.respond_to?(:close) && ! s1.closed?
                s1.join if s1.respond_to?(:join) && ! s1.joined?
                s2.close if s2.respond_to?(:close) && ! s2.closed?
                s2.join if s2.respond_to?(:join) && ! s2.joined?
              end
            ensure
              sout.close if sout.respond_to?(:close) && ! sout.closed?
              sout.join if sout.respond_to?(:join) && ! sout.joined?
            end
          end
          refute Open.exist?(tmp.file)
        end
      end
    end
  end

  def test_tee_stream_save_error_multiple
    Log.with_severity 6 do
      50.times do |i|
        TmpFile.with_file do |tmp|
          Path.setup tmp
          assert_raise ScoutException do
            num = 2000
            begin
              sout = Open.open_pipe do |sin|
                num.times do |i|
                  sin.puts "line #{i} - #{rand(100000).to_s * 100}"
                end
              end

              begin
                s1, s2, s3 = Open.tee_stream_thread_multiple sout, 3

                s2.abort ScoutException.new
                t1 = Open.consume_stream(s1, true, tmp.file1)
                t2 = Open.consume_stream(s2, true, tmp.file2)

                t1.join
                t2.join
              ensure
                s1.close if s1.respond_to?(:close) && ! s1.closed?
                s1.join if s1.respond_to?(:join) && ! s1.joined?
                s2.close if s2.respond_to?(:close) && ! s2.closed?
                s2.join if s2.respond_to?(:join) && ! s2.joined?
                s3.close if s3.respond_to?(:close) && ! s3.closed?
                s3.join if s3.respond_to?(:join) && ! s3.joined?
              end
            ensure
              sout.close if sout.respond_to?(:close) && ! sout.closed?
              sout.join if sout.respond_to?(:join) && ! sout.joined?
            end
          end
          refute Open.exist?(tmp.file1)
          refute Open.exist?(tmp.file2)
        end
      end
    end
  end

  def test_sort_stream
    text =<<-EOF
##
##
##
#Row LabelA LabelB LabelC
row2 AA BB CC
row3 AAA BBB CCC
row1 A B C
    EOF
    s = StringIO.new text
    sorted = Open.sort_stream(s)
    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
       assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
  end

  def test_sort_long_stream
    text =<<-EOF
##
##
##
#Row LabelA LabelB LabelC
row2 AA BB CC
row3 AAA BBB CCC
row1 A B C
    EOF

    s = StringIO.new text + (text.split("\n")[-3..-1] * "\n" + "\n") * 10000
    sorted = Open.sort_stream(s)
    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
    assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
  end

  def test_sort_stream2
    text =<<-EOF
##
##
##
#Row LabelA LabelB LabelC
row2 AA BB CC
row3 AAA BBB CCC
row1 A B C
    EOF
    s = StringIO.new text
    sorted = Open.sort_stream(Open.sort_stream(s))
    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
    assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
  end

  def test_collapse_stream
    text=<<-EOF
row1 A B C
row1 a b c
row2 AA BB CC
row2 aa bb cc
    EOF

    s = StringIO.new text
    stream = Open.collapse_stream(s, sep: " ")
    txt = stream.read
    assert_include txt, "A|a"
    assert_include txt, "B|b"
    assert_include txt, "C|c"
  end


  def test_collapse_sum
    text=<<-EOF
row1 12
row1 4
row2 10
row2 6
    EOF

    s = StringIO.new text
    stream = Open.collapse_stream(s, sep: " ") do |parts|
      next nil if parts.empty?
      parts.first.split("|").collect{|p| p.to_f}.inject(0){|acc,e| acc += e}.to_s
    end
    assert_include stream.read, "row1 16"
  end


  def test_collapse_stream_gap
    text=<<-EOF
row2 AA BB 
row2 aa bb cc
    EOF

    s = StringIO.new text
    assert Open.collapse_stream(s, sep: " ").read =~  /\|cc$/
    
    text=<<-EOF
row2 aa bb cc
row2 AA BB 
    EOF

    s = StringIO.new text
    assert Open.collapse_stream(s, sep: " ").read =~  /cc\|$/

    text=<<-EOF
row2 AA BB
row2 aa bb cc
    EOF

    s = StringIO.new text
    assert Open.collapse_stream(s, sep: " ").read =~  /\|cc$/
  end
  #
  #
  #  def test_paste_stream
  #    text1=<<-EOF
  #row1 A B C
  #row2 AA BB CC
  #row3 AAA BBB CCC
  #    EOF
  #
  #    text2=<<-EOF
  #row1 a b
  #row2 aa bb
  #    EOF
  #
  #    text3=<<-EOF
  #row1 c
  #row2 cc
  #row3 ccc
  #    EOF
  #
  #    s1 = StringIO.new text1
  #    s2 = StringIO.new text2
  #    s3 = StringIO.new text3
  #    tsv = TSV.open Misc.paste_streams([s1,s2,s3], nil, " "), :sep => " ", :type => :list
  #    assert_equal ["A", "B", "C", "a", "b", "c"], tsv["row1"]
  #    assert_equal ["AA", "BB", "CC", "aa", "bb", "cc"], tsv["row2"]
  #    assert_equal ["AAA", "BBB", "CCC", "", "", "ccc"], tsv["row3"]
  #  end
  #
  #  def test_sort_stream
  #    text =<<-EOF
  ###
  ###
  ###
  ##Row LabelA LabelB LabelC
  #row2 AA BB CC
  #row3 AAA BBB CCC
  #row1 A B C
  #    EOF
  #    s = StringIO.new text
  #    sorted = Misc.sort_stream(s)
  #    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
  #    assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
#  end
#
#  def test_sort_long_stream
#    text =<<-EOF
###
###
###
##Row LabelA LabelB LabelC
#row2 AA BB CC
#row3 AAA BBB CCC
#row1 A B C
#    EOF
#
#    s = StringIO.new text + (text.split("\n")[-3..-1] * "\n" + "\n") * 10000
#    sorted = Misc.sort_stream(s)
#    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
#    assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
#  end
#
#  def test_sort_stream2
#    text =<<-EOF
###
###
###
##Row LabelA LabelB LabelC
#row2 AA BB CC
#row3 AAA BBB CCC
#row1 A B C
#    EOF
#    s = StringIO.new text
#    sorted = Misc.sort_stream(Misc.sort_stream(s))
#    assert_equal %w(## ## ## #Row row2 row3 row1), text.split("\n").collect{|l| l.split(" ").first}
#    assert_equal %w(## ## ## #Row row1 row2 row3), sorted.read.split("\n").collect{|l| l.split(" ").first}
#  end
#
#  def test_dup_stream
#    text =<<-EOF
##: :sep=" "
##Row LabelA LabelB LabelC
#row2 AA BB CC
#row3 AAA BBB CCC
#row1 A B C
#    EOF
#
#    text = text * 10000
#    TmpFile.with_file(text) do |tmp|
#      io = Open.open(tmp)
#      dup = Misc.dup_stream(io)
#      new_text = StringIO.new ""
#      Misc.consume_stream dup, true, new_text
#      Misc.consume_stream io, false
#      new_text.rewind
#      assert_equal text, new_text.read
#    end
#
#
#    TmpFile.with_file(text) do |tmp|
#      io = Open.open(tmp)
#      dup = Misc.dup_stream(io)
#      Misc.consume_stream dup, true
#      assert_equal text, io.read
#    end
#  end
#
#  def test_dup_stream_multiple
#    text =<<-EOF
#row2 AA BB CC
#row3 AAA BBB CCC
#row1 A B C
#    EOF
#
#    text = text * 10000
#    num = 5
#    str_io = StringIO.new
#    strs = []
#    num.times{ strs << StringIO.new }
#    TmpFile.with_file(text) do |tmp|
#      io = Open.open(tmp)
#      copies = Misc.dup_stream_multiple(io, num)
#
#
#      copies.each_with_index do |cio,i|
#        cio.add_callback do 
#          str = strs[i] 
#          str.rewind
#          assert_equal text, str.read
#        end
#        Misc.consume_stream cio, true, strs[i], false
#      end
#
#
#      Misc.consume_stream io, false, str_io, false
#      str_io.rewind
#      assert_equal text, str_io.read
#
#    end
#  end
#
#  def test_remove_lines
#    text1 =<<-EOF
#line1
#line2
#line3
#line4
#    EOF
#    text2 =<<-EOF
#line3
#line1
#    EOF
#
#    TmpFile.with_file(text1) do |file1|
#      TmpFile.with_file(text2) do |file2|
#        assert ! Misc.remove_lines(file1, file2, true).read.split("\n").include?("line1")
#        assert Misc.remove_lines(file1, file2, true).read.split("\n").include?("line2")
#      end
#    end
#  end
#
#
#
#  def test_select_lines
#    text1 =<<-EOF
#line1
#line2
#line3
#line4
#    EOF
#    text2 =<<-EOF
#line3
#line1
#line5
#    EOF
#
#    TmpFile.with_file(text1) do |file1|
#      TmpFile.with_file(text2) do |file2|
#        assert Misc.select_lines(file1, file2, true).read.split("\n").include?("line1")
#        assert ! Misc.select_lines(file1, file2, true).read.split("\n").include?("line2")
#      end
#    end
#  end
#
#  def test_consume_into_string_io
#    text =<<-EOF
#line1
#line2
#line3
#line4
#    EOF
#
#    TmpFile.with_file(text) do |file|
#      out = StringIO.new
#      io = Open.open(file)
#      Misc.consume_stream(io, false, out, false)
#      out.rewind
#      assert_equal text, out.read
#    end
#  end
#
#  def test_monitor
#    text =<<-EOF
#line1
#line2
#line3
#line4
#    EOF
#
#    TmpFile.with_file(text) do |file|
#      io = Open.open(file)
#      lines = Set.new
#      io2 = Misc.line_monitor_stream io do |line|
#        lines << line
#      end
#      Misc.consume_stream(io2, false)
#      assert_equal text, lines.to_a * ""
#    end
#  end
#
#  def test_sort
#    assert_raise RbbtException do
#      io = Misc.open_pipe do |sin|
#        sin.puts "#START"
#        20.times do
#          sin.puts rand(1000).to_s
#          sleep 0.1
#        end
#        raise RbbtException
#      end
#
#      sio = Misc.sort_stream(io)
#      begin
#        Misc.consume_stream(sio, false, STDOUT)
#      rescue
#        raise $!
#      end
#    end
#  end
#
#  def test_gz_pipe
#    text =<<-EOF
#line1
#line2
#line3
#line4
#    EOF
#
#    TmpFile.with_file nil, :extension => 'txt.gz' do |file|
#      sout = Misc.open_gz_pipe do |sin|
#        text.split("\n").each do |line|
#          sin.puts line
#        end
#      end
#
#      Open.mkdir File.basename(file)
#      thr1 = Misc.consume_stream(sout, true, file)
#      thr1.join
#      assert Open.gzip?(file)
#      assert_equal text, Open.read(file)
#    end
#  end
#
#  def test_open_pipe_error
#    sout = Misc.open_pipe do |sin|
#      10.times do |i|
#        sin.puts "line #{i}"
#      end
#      raise
#    end
#
#    TmpFile.with_file do |tmp|
#      #Misc.consume_stream(sout, false, tmp)
#      assert_raise do
#        Open.write(tmp, sout)
#      end
#    end
#  end
#end
end

