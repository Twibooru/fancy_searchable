# frozen_string_literal: true
module FancySearchable
  class SearchParsingError < StandardError
  end

  class SearchLexingError < SearchParsingError
  end
end
