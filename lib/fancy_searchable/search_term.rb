require_relative 'relative_date_parser'

module FancySearchable
  class SearchTerm
    attr_accessor :term, :float_fields, :literal_fields, :int_fields, :ngram_fields, :boost, :fuzz
    attr_reader :wildcarded, :ngram_query

    def initialize(term, default_field, options = {})
      @term = term
      allowed_fields = (options[:allowed_fields] || {})
      # List of accepted literal fields.
      @literal_fields = (allowed_fields[:literal] || [])
      # List of accept boolean fields.
      @boolean_fields = (allowed_fields[:boolean] || [])
      # List of NLP-analyzed fields.
      @ngram_fields = (allowed_fields[:full_text] || [])
      # List of date/time fields.
      @date_fields = (allowed_fields[:date] || [])
      # List of floating point fields.
      @float_fields = (allowed_fields[:float] || [])
      # List of integer fields.
      @int_fields = (allowed_fields[:integer] || [])
      # List of allowed IP fields
      @ip_fields = (allowed_fields[:ip] || [])
      @fuzz = options[:fuzz]
      @boost = options[:boost]
      @field_aliases = options[:aliases] || {}
      @field_transforms = options[:transforms] || {}
      @no_downcase = options[:no_downcase] || []
      @default_field = default_field
      @ngram_query = @wildcarded = false
    end

    def append(str)
      @term.concat str.downcase
    end

    def prepend(str)
      @term.prepend(str.downcase)
    end

    def normalize_field_name(field_name)
      if @field_aliases.key?(field_name)
        @field_aliases[field_name]
      else
        field_name
      end
    end

    def normalize_val(field_name, val, range = nil)
      if @int_fields.include?(field_name)
        begin
          val = Integer(val)

          # convert to range
          val = { gte: val - @fuzz, lte: val + @fuzz } if @fuzz && range.nil?
        rescue StandardError
          raise SearchParsingError,
                "Values of \"#{field_name}\" field must be decimal integers; " \
              "\"#{val}\" is invalid."
        end
      elsif @boolean_fields.include?(field_name)
        unless %w[true false].include?(val)
          raise SearchParsingError,
                "Values of \"#{field_name}\" must be \"true\" or \"false\"; " \
              "\"#{val}\" is invalid."
        end
      elsif @ip_fields.include?(field_name)
        begin
          IPAddr.new(val)
        rescue StandardError
          raise SearchParsingError, "Values of \"#{field_name}\" must be IP "\
              "addresses or CIDR ranges; \"#{val}\" is invalid."
        end
      elsif @date_fields.include?(field_name)
        if val.empty?
          raise SearchParsingError,
                "Field \"#{field_name}\" missing date/time value."
        end

        # Convert date into date/time.
        orig_val = val.clone

        # Has an error occurred?
        err = false

        # Ordered arguments used to construct time representations.
        time_data = [nil, nil, nil, nil, nil, nil]
        target_index = -1

        # Get and detach timezone. (The timezone here would default to UTC.)
        timezone = nil
        val.gsub!(/(?:\s*[Zz]|[\+\-]\d{2}:\d{2})$/) do |m|
          timezone = m
          timezone = nil if %w[z Z].include? timezone
          ''
        end

        sym_table = [
          /^(\d{4})/,
          /^\-(\d{2})/,
          /^\-(\d{2})/,
          /^(?:\s+|T|t)(\d{2})/,
          /^:(\d{2})/,
          /^:(\d{2})/
        ]

        higher = lower = nil

        sym_table.each do |re|
          if val.empty?
            break
          else
            target_index += 1
            if val =~ re
              time_data[target_index] = Regexp.last_match[1].to_i
              val.gsub!(re, '')
            else
              err = true
              break
            end
          end
        end

        # Calculate the limits of the required query.
        unless err
          begin
            if timezone.nil?
              lower = Time.utc(*time_data)
            else
              time_data << timezone
              lower = Time.new(*time_data) # rubocop:disable Rails/TimeZone
            end
            return { range.to_sym => lower } if %w[lt gte].include? range
          rescue StandardError
            err = true
          end
        end

        while !err && higher.nil?
          time_data[target_index] += 1
          begin
            higher = if timezone.nil?
                       Time.utc(*time_data)
                     else
                       Time.new(*time_data) # rubocop:disable Rails/TimeZone
                     end
          rescue StandardError
            time_data[target_index] = if target_index < 3
                                        # Days and months roll back to 1.
                                        1
                                      else
                                        0
                                      end
            target_index -= 1
            err = true if target_index < 0
          end
        end

        if err
          higher, lower = RelativeDateParser.parse(orig_val)

          if higher
            return { range.to_sym => lower } if %w[lt gte].include? range

            err = nil # reset error state
          end
        end

        if err
          raise SearchParsingError, "Value \"#{orig_val}\" is not recognized as a valid ISO 8601 date/time."
        elsif range == 'lte'
          return { lt: higher }
        elsif range == 'gt'
          return { gte: higher }
        else
          return { gte: lower, lt: higher }
        end
      elsif @float_fields.include?(field_name)
        begin
          val = Float(val)
          val = { gte: val - @fuzz, lte: val + @fuzz } if @fuzz && range.nil?
        rescue StandardError
          raise SearchParsingError,
                "Values of \"#{field_name}\" field must be decimals."
        end
      elsif !@no_downcase.include?(field_name)
        val = val.downcase
      end

      if %w[lt gt gte lte].include? range
        { range.to_sym => val }
      else
        val
      end
    end

    # Checks any terms with colons for whether a field is specified, and
    # returns an Array: [field, value, extra-options].
    def _escape_colons
      @term.match(/^(.*?[^\\]):(.*)$/) do |m|
        field, val = m[1, 2]
        field.downcase!
        # Range query.
        if field =~ /(.*)\.([gl]te?|eq)$/
          range_field = Regexp.last_match[1].to_sym
          if @date_fields.include?(range_field) ||
            @int_fields.include?(range_field) ||
            @float_fields.include?(range_field)
            return [normalize_field_name(range_field),
                    normalize_val(range_field, val, Regexp.last_match[2])]
          end
        end

        field = field.to_sym

        if @ngram_fields.include?(field)
          @ngram_query = true
        elsif !(@date_fields.include?(field) ||
          @int_fields.include?(field) ||
          @float_fields.include?(field) ||
          @literal_fields.include?(field) ||
          @boolean_fields.include?(field) ||
          @ip_fields.include?(field))
          @ngram_query = @ngram_fields.include?(@default_field)
          return [
            @default_field, normalize_val(@default_field, "#{field}:#{val}")
          ]
        end

        return [normalize_field_name(field), normalize_val(field, val)]
      end
    end

    def parse
      wildcardable = !/^"([^"]|\\")+"$/.match(term)
      @term = @term.slice(1, @term.size - 2) unless wildcardable

      field = nil
      field, value = _escape_colons if @term.include? ':'
      # No colon or #_escape_colons encountered an escaped colon.
      if field.nil?
        @ngram_query = @ngram_fields.include?(@default_field)
        field = @default_field
        value = normalize_val(@default_field, @term)
      end

      return @field_transforms[field].call(value) if @field_transforms[field]

      extra = {}

      # Parse boosting parameter.
      extra[:boost] = @boost.to_f unless @boost.nil?

      if value.is_a? Hash
        return { range: { field => value.merge(extra) } }
      elsif !@fuzz.nil?
        # Parse edit distance parameter.
        normalize_term! value, !wildcardable
        return { fuzzy: { field => { value: value, fuzziness: @fuzz }.merge(extra) } }
      elsif wildcardable && (value =~ /(?:^|[^\\])[\*\?]/)
        # '*' and '?' are wildcard characters in the right context;
        # don't unescape them.
        value.gsub!(/\\([^\*\?])/, '\1')
        # All-matching wildcards merit special treatment.
        @wildcarded = true
        @ngram_query = false
        return { match_all: {} } if value == '*'
        if extra.empty?
          return { wildcard: { field => value } }
        else
          return { wildcard: { field => { value: value }.merge(extra) } }
        end
      elsif @ngram_query
        if extra.empty?
          return { match_phrase: { field => value } }
        else
          return { match_phrase: {
            field => { value: value }.merge(extra)
          } }
        end
      else
        normalize_term!(value, !wildcardable) if value.is_a?(String)
        if extra.empty?
          return { term: { field => value } }
        else
          return { term: { field => { value: value }.merge(extra) } }
        end
      end
    end

    def normalize_term!(match, quoted)
      if quoted
        match.gsub!('\"', '"')
      else
        match.gsub!(/\\(.)/, '\1')
      end
    end

    def to_s
      @term
    end
  end
end