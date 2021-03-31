# frozen_string_literal: true

require 'active_support/all'

module FancySearchable
  module RelativeDateParser
    module_function

    def parse(str, origin = Time.now)
      str = str.squish
      return unless str =~ /\A(\d+) (second|minute|hour|day|week|fortnight|month|year)s? ago\z/

      num = Regexp.last_match(1).to_i
      unit = Regexp.last_match(2)

      higher = num.send(unit).ago(origin)
      lower = higher - 1.send(unit)

      [higher, lower]
    end
  end
end
