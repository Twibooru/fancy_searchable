# frozen_string_literal: true
require 'active_support/core_ext/string'
# Represents a date and time for which some of the parts may be nil.
# This is different from zero, as nil parts are used as placeholders for filling in the minimum
# and maximum values when this NillableDateTime is converted to a Time range.
module FancySearchable
  class NillableDateTime
    attr_reader :zone, :year, :month, :day, :hour, :minute, :second

    def initialize(zone, year, month=nil, day=nil, hour=nil, minute=nil, second=nil)
      @zone = zone
      @year = year
      @month = month
      @day = day
      @hour = hour
      @minute = minute
      @second = second
    end

    def to_a
      [@year, @month, @day, @hour, @minute, @second]
    end

    def range_start
      if @zone
        Time.new(*(to_a + [@zone]))
      else
        Time.utc(*to_a)
      end
    end

    def range_end
      month = @month || 12
      day = @day || Time.days_in_month(month, @year)
      options = [@year,
                 month,
                 day,
                 @hour || 23,
                 @minute || 59,
                 @second || 59]

      if @zone
        Time.new(*(options + [@zone])) + 1
      else
        Time.utc(*options) + 1
      end
    end

    def range
      [range_end, range_start]
    end

    # This is extremely lenient, but it works well and is fast.
    def self.parse(str)
      # Get and detach timezone. (The timezone here would default to UTC.)
      timezone = nil
      str = str.gsub(/(?:\s*[Zz]|[\+\-]\d{2}:\d{2})$/) do |m|
        timezone = m
        timezone = nil if %w[z Z].include? timezone
        ''
      end

      raise 'Date must be present and time must come after date' if str.index(':') && (str.index(':') < str.index('-'))

      parts = str.squish.split(/[-:tT\s]/).map(&:to_i)

      NillableDateTime.new(timezone, *parts)
    end
  end
end
