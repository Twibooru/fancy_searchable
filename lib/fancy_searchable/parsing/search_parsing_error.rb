# frozen_string_literal: true
module FancySearchable
  module Parsing
    class SearchParsingError < StandardError
    end

    class SearchLexingError < SearchParsingError
    end
  end
end
