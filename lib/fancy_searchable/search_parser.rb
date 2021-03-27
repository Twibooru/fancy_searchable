# frozen_string_literal: true

require 'active_support/all'
require 'time'
require_relative 'search_term'
require_relative 'search_parsing_error'
require_relative 'relative_date_parser'

module FancySearchable
  class SearchParser
    attr_reader :search_str, :requires_query, :allowed_fields

    TOKEN_LIST = [
      [:fuzz, /^~(?:\d+(\.\d+)?|\.\d+)/],
      [:boost, /^\^[\-\+]?\d+(\.\d+)?/],
      [:quoted_lit, /^\s*"(?:(?:[^"]|\\")+)"/],
      [:lparen, /^\s*\(\s*/],
      [:rparen, /^\s*\)\s*/],
      [:and_op, /^\s*(?:\&\&|AND)\s+/],
      [:and_op, /^\s*,\s*/],
      [:or_op, /^\s*(?:\|\||OR)\s+/],
      [:not_op, /^\s*NOT(?:\s+|(?>\())/],
      [:not_op, /^\s*[\!\-]\s*/],
      [:space, /^\s+/],
      [:word, /^(?:[^\s,\(\)\^~]|\\[\s,\(\)\^~])+/],
      [:word, /^(?:[^\s,\(\)]|\\[\s,\(\)])+/]
    ].freeze

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

    def _flatten_operands(ops, operator, negate)
      # The Boolean operator type.
      bool = _bool_to_es_op operator
      # The query AST thus far.
      query = {}
      # Build the Array of operands based on the unifying operator.
      bool_stack = []
      ops.each do |op_type, negate_term, op|
        if op_type == :term && negate_term
          # Term negation.
          op = { bool: { must_not: [op] } }
        end
        bool_exp = op[:bool]
        if !bool_exp.nil? && bool_exp.keys.size == 1 && bool_exp.key?(bool)
          bool_stack.concat bool_exp[bool]
        elsif bool_exp.nil? || !bool_exp.keys.empty?
          bool_stack.push op
        end
      end
      query[bool] = bool_stack unless bool_stack.empty?

      # Negation of the AST Hash.
      if negate
        if query.keys.size == 1 && query.key?(:must_not)
          return [:subexp, false, { bool: { must: query[:must_not] } }]
        else
          # Return point when explicit negation at the AST root is needed.
          return [:subexp, false, { bool: { must_not: [{ bool: query }] } }]
        end
      end
      [:subexp, false, { bool: query }]
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
      @tokens ||= _lex
    end

    def new_search_term(term_str)
      SearchTerm.new(
        term_str.lstrip,
        @default_field,
        allowed_fields: @allowed_fields,
        aliases:        @field_aliases,
        transforms:     @field_transforms,
        no_downcase:    @no_downcase
      )
    end

    def _lex
      # Queue of operators.
      ops = []
      # Search term storage between match iterations, for multi-word
      # search results and special cases.
      search_term = boost = fuzz = nil
      # Count any left parentheses within the actual search term?
      lparen_in_term = 0
      # Negation of a single term.
      negate = false
      # Negation of a subexpression.
      group_negate = []
      # Stack of terms and operators shifted from queue.
      token_stack = []
      # The string containing the match and boost expressions matched thus
      # far, should the term ultimately not have a proper match/boost syntax.
      boost_fuzz_str = +''

      # Shunting-yard algorithm, to convert to a postfix-style IR.
      until @search_str.empty?
        TOKEN_LIST.each do |token|
          symbol, regexp = token
          match = regexp.match @search_str
          next unless match

          match = match.to_s

          # Add the current search term to the stack once we have reached
          # another operator.
          if (%i[and_op or_op].include? symbol) || (
            symbol == :rparen && lparen_in_term == 0)
            if search_term
              # Set options data.
              search_term.boost = boost
              search_term.fuzz  = fuzz
              # Push to stack.
              token_stack.push search_term
              # Reset term and options data.
              search_term = fuzz = boost = nil
              boost_fuzz_str = +''
              lparen_in_term = 0
              if negate
                token_stack.push :not_op
                negate = false
              end
            end
          end

          # React to the token type that we have matched.
          case symbol
          when :and_op
            token_stack.push(ops.shift) while ops[0] == :and_op
            ops.unshift :and_op
          when :or_op
            token_stack.push(ops.shift) while %i[and_op or_op].include?(ops[0])
            ops.unshift :or_op
          when :not_op
            if search_term
              # We're already inside a search term, so it does
              # not apply, obv.
              search_term.append match
            else
              negate = !negate
            end
          when :lparen
            if search_term
              # If we are inside the search term, do not error out
              # just yet; instead, consider it as part of the search
              # term, as a user convenience.
              search_term.append match
              lparen_in_term += 1
            else
              ops.unshift :lparen
              group_negate.push negate
              negate = false
            end
          when :rparen
            if lparen_in_term != 0
              search_term.append match
              lparen_in_term -= 1
            else
              # Shift operators until a right parenthesis is encountered.
              balanced = false
              until ops.empty?
                op = ops.shift
                if op == :lparen
                  balanced = true
                  break
                end
                token_stack.push op
              end
              raise SearchParsingError, 'Imbalanced parentheses.' unless balanced

              token_stack.push :not_op if group_negate.pop
            end
          when :fuzz
            if search_term
              fuzz = match[1..-1].to_f
              # For this and boost operations, we store the current match
              # so far to a temporary string in case this is actually
              # inside the term.
              boost_fuzz_str.concat match
            else
              search_term = new_search_term match
            end
          when :boost
            if search_term
              boost = match[1..-1]
              boost_fuzz_str.concat match
            else
              search_term = new_search_term match
            end
          when :quoted_lit
            if search_term
              search_term.append match
            else
              search_term = new_search_term match
            end
          when :word
            # Part of an unquoted literal.
            if search_term
              if fuzz || boost
                boost = fuzz = nil
                search_term.append boost_fuzz_str
                boost_fuzz_str = +''
              end

              search_term.append match
            else
              search_term = new_search_term match
            end
          else
            # Append extra spaces within search terms.
            search_term.append(match) if search_term
          end

          # Truncate string and restart the token tests.
          @search_str = @search_str.slice(match.size,
                                          @search_str.size - match.size)
          break
        end
      end

      # Append final tokens to the stack, starting with the search term.
      if search_term
        search_term.boost = boost
        search_term.fuzz = fuzz
        token_stack.push search_term
      end
      token_stack.push(:not_op) if negate

      raise SearchParsingError, 'Imbalanced parentheses.' if ops.any? { |x| %i[rparen lparen].include?(x) }

      token_stack.concat ops

      token_stack
    end
  end
end
