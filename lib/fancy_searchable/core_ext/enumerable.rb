# frozen_string_literal: true
module Enumerable
  def _fs_detect
    each do |value|
      result = yield value

      return result if result[1]
    end
  end
end
