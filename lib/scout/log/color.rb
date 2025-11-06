require_relative 'color_class'
require_relative '../indiferent_hash'

require 'term/ansicolor'

module Colorize
  def self.colors=(colors)
    @colors = colors
  end

  def self.colors
    @colors ||= IndiferentHash.setup(Hash[<<-EOF.split("\n").collect{|l| l.split(" ")}])
green #00cd00
red #cd0000
yellow #ffd700
blue #0000cd
path blue
EOF
  end

  def self.diverging_colors=(colors)
    @diverging_colors = colors
  end

  def self.diverging_colors
    @diverging_colors ||=<<~EOF.split("\n")
      #a6cee3
      #1f78b4
      #b2df8a
      #33a02c
      #fb9a99
      #e31a1c
      #fdbf6f
      #ff7f00
      #cab2d6
      #6a3d9a
      #ffff99
      #b15928
    EOF
  end

  def self.from_name(color)
    return color if color =~ /^#?[0-9A-F]+$/i
    return colors[color.to_s] if colors.include?(color.to_s)

    case color.to_s
    when "white"
      '#000'
    when "black"
      '#fff'
    when 'green'
      colors["green3"]
    when 'red'
      colors["red3"]
    when 'yellow'
      colors["gold1"]
    when 'blue'
      colors["RoyalBlue"]
    else
      colors[color.to_s] || color.to_s
    end
  end

  def self.continuous(array, start = "#40324F", eend = "#EABD5D", percent = false)
    start_color = Color.new from_name(start)
    end_color = Color.new from_name(eend)

    if percent
      array = array.collect{|v| n = v.to_f; n = n > 100 ? 100 : n; n < 0.001 ? 0.001 : n}
    else
      array = array.collect{|v| v.to_f }
    end
    max = array.max
    min = array.min
    range = max - min
    array.collect do |v|
      ratio = (v.to_f-min) / range
      start_color.blend end_color, ratio
    end
  end

  def self.gradient(array, value, start = :green, eend = :red, percent = false)
    index = array.index value
    colors = continuous(array, start, eend, percent)
    colors[index]
  end

  def self.rank_gradient(array, value, start = :green, eend = :red, percent = false)
    index = array.index value
    sorted = array.sort
    array = array.collect{|e| sorted.index e}
    colors = continuous(array, start, eend, percent)
    colors[index]
  end


  def self.distinct(array)
    colors = diverging_colors.collect{|c| Color.new c }

    num = array.uniq.length
    times = num / 12

    all_colors = colors.dup
    factor = 0.3 / times
    times.times do
      all_colors.concat  colors.collect{|n| n.darken(factor) }
    end

    value_color = Hash[*array.uniq.zip(all_colors).flatten]

    value_color.values_at(*array)
  end

  def self.tsv(tsv, options = {})
    values = tsv.values.flatten
    if Numeric === values.first or (values.first.to_f != 0 and values[0] != "0" and values[0] != "0.0")
      value_colors = IndiferentHash.process_to_hash(values){continuous(values)}
    else
      value_colors = IndiferentHash.process_to_hash(values){distinct(values)}
    end

    if tsv.type == :single
      Hash[*tsv.keys.zip(value_colors.values_at(*values)).flatten]
    else
      Hash[*tsv.keys.zip(values.collect{|vs| value_colors.values_at(*vs)}).flatten]
    end
  end
end

module Log
  extend Term::ANSIColor

  class << self
    attr_accessor :nocolor
  end

  self.nocolor = ENV["SCOUT_NOCOLOR"] == 'true'

  WHITE, DARK, GREEN, YELLOW, RED = Color::SOLARIZED.values_at :base0, :base00, :green, :yellow, :magenta

  SEVERITY_COLOR = [reset, cyan, green, magenta, blue, yellow, red] #.collect{|e| "\033[#{e}"}
  CONCEPT_COLORS = IndiferentHash.setup({
    :title => magenta,
    :subtitle => yellow,
    :body => blue,
    :path => blue,
    :input => cyan,
    :value => green,
    :integer => green,
    :negative => red,
    :float => green,
    :waiting => yellow,
    :started => cyan,
    :start => cyan,
    :done => green,
    :error => red,
    :time => cyan,
    :task => yellow,
    :workflow => yellow,
    :present => green,
    :missing => cyan,
  })
  HIGHLIGHT = "\033[1m"

  def self.uncolor(str)
    "" + Term::ANSIColor.uncolor(str)
  end

  def self.reset_color
    reset
  end

  def self.color(color, str = nil, reset = false)
    return str.to_s.dup if nocolor

    if (color == :integer || color == :float) && Numeric === str
      color = if str < 0
                :red
              elsif str > 1
                :cyan
              else
                :green
              end
    end

    if color == :status
      color = case str.to_sym
              when :done
                :green
              when :error, :aborted
                :red
              when :waiting, :queued
                :yellow
              when :started, :streamming
                :cyan
              when :start
                :title
              else
                :cyan
              end
    end

    color = SEVERITY_COLOR[color] if Integer === color
    color = CONCEPT_COLORS[color] if CONCEPT_COLORS.include?(color)
    color = Term::ANSIColor.send(color) if Symbol === color and Term::ANSIColor.respond_to?(color)

    str = str.to_s unless str.nil?
    return str if Symbol === color
    color_str = reset ? Term::ANSIColor.reset.dup : ""
    color_str += color if color
    if str.nil?
      color_str
    else
      color_str + str.to_s + Term::ANSIColor.reset
    end
  end

  def self.highlight(str = nil)
    if str.nil?
      return "" if nocolor
      HIGHLIGHT
    else
      return str if nocolor
      HIGHLIGHT + str + color(0)
    end
  end

end
