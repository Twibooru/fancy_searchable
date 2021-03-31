# frozen_string_literal: true
require 'active_support/core_ext/string'
module FancySearchable
  class NillableDateTime
    attr_reader :year, :month, :day, :hour, :minute, :second

    def initialize(year, month=nil, day=nil, hour=nil, minute=nil, second=nil)
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

    def range_start(zone = nil)
      if zone
        Time.new(*(to_a + [zone]))
      else
        Time.utc(*to_a)
      end
    end

    def range_end(zone = nil)
      month = @month || 12
      day = @day || Time.days_in_month(month, @year)
      options = [@year,
                 month,
                 day,
                 @hour || 23,
                 @minute || 59,
                 @second || 59]

      if zone
        Time.new(*(options + [zone])) + 1
      else
        Time.utc(*options) + 1
      end
    end

    def self.parse(str)
      parts = str.squish.split(/[-:tT\s]/).map(&:to_i)

      NillableDateTime.new(*parts)
    end
  end
end
