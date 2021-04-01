# frozen_string_literal: true

require 'active_support/all'
require 'time'
require_relative 'search_term'
require_relative 'search_lexer'
require_relative 'search_parsing_error'

module FancySearchable
  module Parsing
    class SearchParser
      attr_reader :search_str, :requires_query, :allowed_fields

      def initialize(search_str, default_field, options = {})
        @search_str = search_str.strip
        # State variable indicating whether fuzz or boosting is used, which
        # mandates embedding the respective query AST in a query (instead
        # of a more efficient filter).
        @requires_query = false
        # Default search field.
        @default_field = default_field
        @allowed_fields = options[:allowed_fields]
        # Hash describing aliases to target ES fields.
        (@field_aliases = options[:field_aliases]) || {}
        (@field_transforms = options[:field_transforms]) || {}
        (@no_downcase = options[:no_downcase]) || []
        @parsed = _parse
      end

      def _bool_to_es_op(operator)
        if operator == :and_op
          :must
        else
          :should
        end
      end

      # @param ops List of operands that we're trying to flatten, could be a couple literals, could be other stuff.
      # @param operator How we want to combine the operands
      # @param negate_result Whether we want to negate the result
      def _flatten_operands(ops, operator, negate_result)
        bool_op_type = _bool_to_es_op operator
        boolses = []

        ops.each do |type, negate, op|
          if type == :term && negate
            op = { bool: { must_not: [op] } }
          end

          bool_exp = op[:bool]

          if bool_exp && bool_exp.keys.size == 1 && bool_exp.key?(bool_op_type)
            boolses += bool_exp[bool_op_type]
          elsif bool_exp.nil? || !bool_exp.keys.empty?
            boolses.push op
          end
        end

        raise 'What?' if boolses.empty? # Should we get here? I hope not, that would be a little weird.

        query = { bool_op_type => boolses }

        if negate_result
          if bool_op_type == :must_not
            [:subexp, false, { bool: { must: boolses } }]
          else
            [:subexp, false, { bool: { must_not: [{ bool: query }] } }]
          end
        else
          [:subexp, false, { bool: query }]
        end
      end

      def _parse
        # Stack for search terms and earlier combinations of search terms.
        operand_stack = []
        tokens.each_with_index do |token, idx|
          next if token == :not_op

          # Negation immediately follows the current token or operator.
          negate = (tokens[idx + 1] == :not_op)
          if token.is_a? SearchTerm
            parsed = token.parse
            @requires_query = true if token.wildcarded || token.fuzz || token.boost || token.ngram_query
            # Each operand is encoded as an Array containing the type
            # of operand (term or subexpressions), whether it is
            # negated, the actual term or subexpression as an ES-compliant
            # Hash, and a key map enumerating any undoable flattening,
            # which is null for terms
            operand_stack.push [:term, negate, parsed]
          else
            op_2 = operand_stack.pop
            op_1 = operand_stack.pop
            raise SearchParsingError, 'Missing operand.' if op_1.nil? || op_2.nil?

            operand_stack.push _flatten_operands([op_1, op_2], token, negate)
          end
        end

        raise SearchParsingError, 'Missing operator.' if operand_stack.size > 1

        op = operand_stack.pop

        if op.nil?
          {}
        else
          negate = op[1]
          exp = op[2]

          negate ? { bool: { must_not: [exp] } } : exp
        end
      end

      def parsed
        @parsed.presence || { match_none: {} }
      end

      def tokens
        @tokens ||= SearchLexer.lex(@search_str).map { |t| t.is_a?(String) ? new_search_term(t) : t }
      end

      def new_search_term(term_str)
        SearchTerm.new(
          term_str,
          @default_field,
          allowed_fields: @allowed_fields,
          aliases:        @field_aliases,
          transforms:     @field_transforms,
          no_downcase:    @no_downcase
        )
      end
    end
  end
end
