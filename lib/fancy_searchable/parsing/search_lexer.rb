# frozen_string_literal: true
require_relative 'search_parsing_error'
require_relative '../core_ext/enumerable'

module FancySearchable
  module Parsing
    class SearchLexer
      TOKEN_LIST = [
        [:quoted_lit, /^\s*"(?:(?:[^"]|\\")+)"/],
        [:lparen,     /^\(/],
        [:rparen,     /^\)/],
        [:and_op,     /^(?:&&|AND|,)/],
        # [:and_op,     /^,/],
        [:or_op,      /^(?:\|\||OR)/],
        [:not_op,     /^NOT(?:\s+|(?>\())/], # TODO: What?
        [:not_op,     /^[!\-]/],
        [:space,      /^\s+/],
        [:word,       /^(?:[^\s,()]|\\[\s,()])+/]
      ].freeze

      def self.lex(search_str)
        # Queue of operators.
        ops = []
        # Search term storage between match iterations, for multi-word
        # search results and special cases.
        search_term = nil
        # Count any left parentheses within the actual search term?
        lparen_in_term = 0
        # Negation of a single term.
        negate = false
        # Negation of a subexpression.
        group_negate = []
        # Stack of terms and operators shifted from queue.
        token_stack = []

        # Shunting-yard algorithm, to convert to a postfix-style IR.
        until search_str.empty?
          symbol, match = TOKEN_LIST._fs_detect { |sym, regexp| [sym, regexp.match(search_str)] }

          raise SearchLexingError, 'Failed to match a token' unless match

          match = match.to_s

          # Add the current search term to the stack once we have reached
          # another operator.
          if (%i[and_op or_op].include? symbol) || (
            symbol == :rparen && lparen_in_term == 0)
            if search_term
              # Push to stack.
              token_stack.push search_term.strip
              # Reset term and options data.
              search_term = nil
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
              search_term += match
            else
              negate = !negate
            end
          when :lparen
            if search_term
              # If we are inside the search term, do not error out
              # just yet; instead, consider it as part of the search
              # term, as a user convenience.
              search_term += match
              lparen_in_term += 1
            else
              ops.unshift :lparen
              group_negate.push negate
              negate = false
            end
          when :rparen
            if lparen_in_term != 0
              search_term += match
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

              raise SearchLexingError, 'Imbalanced parentheses.' unless balanced

              token_stack.push :not_op if group_negate.pop
            end
          when :word, :quoted_lit
            if search_term
              search_term += match
            else
              search_term = match
            end
          else
            # Append extra spaces within search terms.
            search_term += match if search_term
          end

          # Truncate string and restart the token tests.
          search_str = search_str.slice(match.size,
                                        search_str.size - match.size)
        end

        # Append final tokens to the stack, starting with the search term.
        if search_term
          token_stack.push search_term.strip
        end

        token_stack.push(:not_op) if negate

        raise SearchLexingError, 'Imbalanced parentheses.' if ops.any? { |x| %i[rparen lparen].include?(x) }

        token_stack.concat ops

        token_stack
      end
    end
  end
end
