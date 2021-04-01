require 'rspec'
require 'fancy_searchable'

RSpec.describe FancySearchable::Parsing::SearchParser do
  def tags_parser(expr, options = {})
    FancySearchable::Parsing::SearchParser.new(expr, 'namespaced_tags.name', options)
  end

  def parse(expr, options = {})
    tags_parser(expr, options).parsed
  end

  describe 'the basics' do
    it 'should return match_none for an empty search' do
      expect(parse('')).to eq({ match_none: {} })
    end

    it 'should return a single term for a single search' do
      expect(parse('twilight sparkle')).to eq({ term: { 'namespaced_tags.name' => 'twilight sparkle' } })
    end

    it 'should allow implicit wildcards' do
      parser = tags_parser('*test*')

      expect(parser.parsed).to eq({ wildcard: { 'namespaced_tags.name' => '*test*' } })
      expect(parser.requires_query).to eq true
    end
  end

  describe 'errors' do
    it 'should validate integer fields' do
      expect { tags_parser('score:potato', allowed_fields: { integer: [:score] }) }.to raise_error FancySearchable::Parsing::SearchParsingError
    end

    it 'should validate float fields' do
      expect { tags_parser('score:potato', allowed_fields: { float: [:score] }) }.to raise_error FancySearchable::Parsing::SearchParsingError
    end

    it 'should validate boolean fields' do
      expect { tags_parser('is_cool:maybe', allowed_fields: { boolean: [:is_cool] }) }.to raise_error FancySearchable::Parsing::SearchParsingError
    end

    it 'should validate date fields' do
      expect { tags_parser('created_at:not a date', allowed_fields: { date: [:created_at] }) }.to raise_error FancySearchable::Parsing::SearchParsingError
    end

    it 'should validate ip fields' do
      expect { tags_parser('ip:definitely.not.an.ip', allowed_fields: { ip: [:ip] }) }.to raise_error FancySearchable::Parsing::SearchParsingError
    end
  end

  describe 'escaping' do
    it 'should support escaping characters with backslashes' do
      parsed = parse('\"pinkie\: the \pie\" \(\*cosplayer\*\)')

      expect(parsed).to eq({ term: { 'namespaced_tags.name' => '"pinkie: the pie" (*cosplayer*)' } })
    end

    it 'should support escaping characters with surrounding double quotes' do
      parsed = parse('"\"pinkie: the pie\" (*cosplayer*)"')

      expect(parsed).to eq({ term: { 'namespaced_tags.name' => '"pinkie: the pie" (*cosplayer*)' } })
    end

    it 'should support double quotes in terms without escaping them' do
      parsed = parse('element of laughter* "pinkie pie"')

      expect(parsed).to eq({ wildcard: { 'namespaced_tags.name' => 'element of laughter* "pinkie pie"' } })
    end
  end

  describe 'boolean methods' do
    it 'should support an AND query' do
      parsed = parse('twilight sparkle AND starlight glimmer')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'twilight sparkle' } },
        { term: { 'namespaced_tags.name' => 'starlight glimmer' } }
      ] } })
    end

    it 'should support an AND query with condensed commas' do
      parsed = parse('twilight sparkle,starlight glimmer')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'twilight sparkle' } },
        { term: { 'namespaced_tags.name' => 'starlight glimmer' } }
      ] } })
    end

    it 'should support an OR query' do
      parsed = parse('twilight sparkle || starlight glimmer')

      expect(parsed).to eq({ bool: { should: [
        { term: { 'namespaced_tags.name' => 'twilight sparkle' } },
        { term: { 'namespaced_tags.name' => 'starlight glimmer' } }
      ] } })
    end

    it 'should support a NOT query' do
      parsed = parse('NOT fluttershy')

      expect(parsed).to eq({ bool: { must_not: [
        { term: { 'namespaced_tags.name' => 'fluttershy' } }
      ] } })
    end

    it 'supports stacked NOT operators as expected' do
      parsed = parse('!!!!flutterbat,!!!fluttershy')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'flutterbat' } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'fluttershy' } }
        ] } }
      ] } })
    end

    it 'supports NOT operations inside AND expressions' do
      parsed = parse('twilight sparkle && !pinkie pie')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'twilight sparkle' } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'pinkie pie' } }
        ] } }
      ] } })
    end

    it 'supports NOT operations inside OR expressions' do
      parsed = parse('NOT pinkie pie || !fluttershy')

      expect(parsed).to eq({ bool: { should: [
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'pinkie pie' } }
        ] } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'fluttershy' } }
        ] } }
      ] } })
    end

    describe 'negation' do
      it 'should negate an AND expression when preceded by a NOT operation' do
        parsed = parse('!(pinkie pie, twilight sparkle)')

        expect(parsed).to eq({ bool: { must_not: [
          { bool: { must: [
            { term: { 'namespaced_tags.name' => 'pinkie pie' } },
            { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
          ] } }
        ] } })
      end

      it 'should negate an OR expression when preceded by a NOT operation' do
        parsed = parse('!(pinkie pie || twilight sparkle)')

        expect(parsed).to eq({ bool: { must_not: [
          { bool: { should: [
            { term: { 'namespaced_tags.name' => 'pinkie pie' } },
            { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
          ] } }
        ] } })
      end

      it 'should negate a parenthesized sub-expression linked by AND' do
        parsed = parse('!(pinkie pie || twilight sparkle) && rarity')

        expect(parsed).to eq({ bool: { must: [
          { bool: { must_not: [
            { bool: { should: [
              { term: { 'namespaced_tags.name' => 'pinkie pie' } },
              { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
            ] } }
          ] } },
          { term: { 'namespaced_tags.name' => 'rarity' } }
        ] } })
      end

      it 'should negate a parenthesized sub-expression linked by OR' do
        parsed = parse('NOT (pinkie pie || !fluttershy && apple bloom) || applejack')

        expect(parsed).to eq({ bool: { should: [
          { bool: { must_not: [
            { bool: { should: [
              { term: { 'namespaced_tags.name' => 'pinkie pie' } },
              { bool: { must: [
                { bool: { must_not: [
                  { term: { 'namespaced_tags.name' => 'fluttershy' } }
                ] } },
                { term: { 'namespaced_tags.name' => 'apple bloom' } }
              ] } }
            ] } }
          ] } },
          { term: { 'namespaced_tags.name' => 'applejack' } }
        ] } })
      end

      it 'should negate a whole complex expression' do
        parsed = parse('!((pinkie pie || twilight sparkle) && applejack)')

        expect(parsed).to eq({ bool: { must_not: [
          { bool: { must: [
            { bool: { should: [
              { term: { 'namespaced_tags.name' => 'pinkie pie' } },
              { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
            ] } },
            { term: { 'namespaced_tags.name' => 'applejack' } }
          ] } }
        ] } })
      end

      it 'should handle minus signs inside terms appropriately' do
        parsed = parse('a - b')

        expect(parsed).to eq({ term: { 'namespaced_tags.name' => 'a - b' } })
      end
    end
  end

  describe 'order of operations' do
    it 'should support parenthesized sub-expressions' do
      parsed = parse('((pinkie pie && twilight sparkle) || applejack) && apple bloom')

      expect(parsed).to eq({ bool: { must: [
        { bool: { should: [
          { bool: { must: [
            { term: { 'namespaced_tags.name' => 'pinkie pie' } },
            { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
          ] } },
          { term: { 'namespaced_tags.name' => 'applejack' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'apple bloom' } }
      ] } })
    end

    it 'should maintain the correct order of operations' do
      parsed = parse('pinkie pie && !fluttershy || apple bloom && applejack')

      expect(parsed).to eq({ bool: { should: [
        { bool: { must: [
          { term: { 'namespaced_tags.name' => 'pinkie pie' } },
          { bool: { must_not: [
            { term: { 'namespaced_tags.name' => 'fluttershy' } }
          ] } }
        ] } },
        { bool: { must: [
          { term: { 'namespaced_tags.name' => 'apple bloom' } },
          { term: { 'namespaced_tags.name' => 'applejack' } }
        ] } }
      ] } })
    end

    it 'should flatten a chain of AND operations while preserving order' do
      parsed = parse('pinkie pie && !twilight sparkle,!fluttershy && bats!')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'pinkie pie' } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
        ] } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'fluttershy' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'bats!' } }
      ] } })
    end

    it 'should flatten a chain of OR operations while preserving order' do
      parsed = parse('pinkie pie || !twilight sparkle OR !fluttershy || bats!')

      expect(parsed).to eq({ bool: { should: [
        { term: { 'namespaced_tags.name' => 'pinkie pie' } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'twilight sparkle' } }
        ] } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'fluttershy' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'bats!' } }
      ] } })
    end

    it 'should maintain correct order of operations with wildcards' do
      parsed = parse('pinkie* || !flutter* && apple* || applejack')

      expect(parsed).to eq({ bool: { should: [
        { wildcard: { 'namespaced_tags.name' => 'pinkie*' } },
        { bool: { must: [
          { bool: { must_not: [
            { wildcard: { 'namespaced_tags.name' => 'flutter*' } }
          ] } },
          { wildcard: { 'namespaced_tags.name' => 'apple*' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'applejack' } }
      ] } })
    end

    it 'should handle redundant parentheses' do
      parsed = parse('(pinkie pie || (!fluttershy && apple*) || (applejack))')

      expect(parsed).to eq({ bool: { should: [
        { term: { 'namespaced_tags.name' => 'pinkie pie' } },
        { bool: { must: [
          { bool: { must_not: [
            { term: { 'namespaced_tags.name' => 'fluttershy' } }
          ] } },
          { wildcard: { 'namespaced_tags.name' => 'apple*' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'applejack' } }
      ] } })
    end

    it 'should permit parentheses to form part of search terms when necessary' do
      parsed = parse('pinkie pie (cosplayer),(-fluttershy (pony),apple (fruit))')

      expect(parsed).to eq({ bool: { must: [
        { term: { 'namespaced_tags.name' => 'pinkie pie (cosplayer)' } },
        { bool: { must_not: [
          { term: { 'namespaced_tags.name' => 'fluttershy (pony)' } }
        ] } },
        { term: { 'namespaced_tags.name' => 'apple (fruit)' } }
      ] } })
    end

    it 'should handle nested sub-expressions' do
      parsed = parse('((score.gt:100 || upvotes.gt:100), (comment_count:50 || !(pinkie pie, cat))) || faved_by:pony pony',
                     allowed_fields: {
                       integer: [:comment_count, :ponies, :score, :upvotes],
                       literal: [:faved_by]
                     },
                     field_aliases:  { faved_by: :favourited_by })

      expect(parsed).to eq({ bool: { should: [
        { bool: { must: [
          { bool: { should: [
            { range: { score: { gt: 100 } } },
            { range: { upvotes: { gt: 100 } } }
          ] } },
          { bool: { should: [
            { term: { comment_count: 50 } },
            { bool: { must_not: [
              { bool: { must: [
                { term: { 'namespaced_tags.name' => 'pinkie pie' } },
                { term: { 'namespaced_tags.name' => 'cat' } }
              ] } }
            ] } }
          ] } }
        ] } },
        { term: { favourited_by: 'pony pony' } }
      ] } })
    end
  end

  describe 'field transforms' do
    it 'should transform aliased fields to actual target fields' do
      parsed =  parse(
        'faved_by:k_a',
        allowed_fields: { literal: [:faved_by] },
        field_aliases:  { faved_by: :favourited_by_users }
      )

      expect(parsed).to eq({ term: { favourited_by_users: 'k_a' } })
    end

    it 'should transform fields according to defined functions' do
      parsed =  parse(
        'k_a',
        field_transforms: { 'namespaced_tags.name' => ->(x) { { term: { 'namespaced_tags.name' => x.sub('_', ' ') } } } }
      )

      expect(parsed).to eq({ term: { 'namespaced_tags.name' => 'k a' } })

      # TODO: What does this test that the above expectation does not?
      expect(parse(
               'emotion:happy',
               allowed_fields:   { literal: [:emotion] },
               field_transforms: { emotion: ->(x) { { term: { emotion: x.replace('^_^') } } } }
             )).to eq({ term: { emotion: '^_^' } })
    end

    it 'should support custom literal fields when defined' do
      parsed = parse(
        'uploader:k_a || artist:k-anon',
        allowed_fields: { literal: [:uploader] }
      )

      expect(parsed).to eq({ bool: { should: [
        { term: { uploader: 'k_a' } },
        { term: { 'namespaced_tags.name' => 'artist:k-anon' } }
      ] } })
    end

    it 'should ignore custom literal fields when not defined' do
      parsed = parse('uploader:k_a || artist:k-anon')

      expect(parsed).to eq({ bool: { should: [
        { term: { 'namespaced_tags.name' => 'uploader:k_a' } },
        { term: { 'namespaced_tags.name' => 'artist:k-anon' } }
      ] } })
    end
  end

  describe 'fuzzy and boosting' do
    it 'should support fuzzy queries' do
      parser = tags_parser(
        'uploader:k_a~1.00 || artist:k-anon || "lyra hortstrings"~0.9',
        allowed_fields: { literal: [:uploader] }
      )

      expect(parser.parsed).to eq({ bool: { should: [
        { fuzzy: { uploader: {
          value:     'k_a',
          fuzziness: 1.0
        } } },
        { term: { 'namespaced_tags.name' => 'artist:k-anon' } },
        { fuzzy: { 'namespaced_tags.name' => {
          value:     'lyra hortstrings',
          fuzziness: 0.9
        } } }
      ] } })

      expect(parser.requires_query).to eq true
    end

    it 'should support boosting terms' do
      parser = tags_parser(
        'uploader:k_a^-1 || artist:k-anon || "lyra heartstrings"^5.3',
        allowed_fields: { literal: [:uploader] }
      )

      expect(parser.parsed).to eq({ bool: { should: [
        { term: { uploader: {
          value: 'k_a',
          boost: -1
        } } },
        { term: { 'namespaced_tags.name' => 'artist:k-anon' } },
        { term: { 'namespaced_tags.name' => {
          value: 'lyra heartstrings',
          boost: 5.3
        } } }
      ] } })

      expect(parser.requires_query).to eq true
    end

    it 'should support boosting fuzzy queries' do
      parser = tags_parser(
        'uploader:k_a~1.00^3 || artist:k-anon || "lyra hortstrings"^78~0.9',
        allowed_fields: { literal: [:uploader] }
      )

      expect(parser.parsed).to eq({ bool: { should: [
        { fuzzy: { uploader: {
          value:     'k_a',
          boost:     3,
          fuzziness: 1.0
        } } },
        { term: { 'namespaced_tags.name' => 'artist:k-anon' } },
        { fuzzy: { 'namespaced_tags.name' => {
          value:     'lyra hortstrings',
          boost:     78,
          fuzziness: 0.9
        } } }
      ] } })

      expect(parser.requires_query).to eq true
    end
  end

  describe 'ranges' do
    it 'should support range fields' do
      parsed = parse('(score.gt:100 || upvotes.gt:100), comment_count:50',
                     allowed_fields: { integer: [:comment_count, :ponies, :score, :upvotes] })

      expect(parsed).to eq({ bool: { must: [
        { bool: { should: [
          { range: { score: { gt: 100 } } },
          { range: { upvotes: { gt: 100 } } }
        ] } },
        { term: { comment_count: 50 } }
      ] } })
    end
  end

  describe 'dates' do
    it 'should support searching through a year' do
      parsed = parse('created_at:2015',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-01-01T00:00:00Z'.to_time,
        lt:  '2016-01-01T00:00:00Z'.to_time
      } } })
    end

    it 'should support searching through a year with provided time zone' do
      parsed = parse('created_at:2015+08:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-01-01T00:00:00+08:00'.to_time,
        lt:  '2016-01-01T00:00:00+08:00'.to_time
      } } })
    end

    it 'should support searching through a month' do
      parsed = parse('created_at:2015-04',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00Z'.to_time,
        lt:  '2015-05-01T00:00:00Z'.to_time
      } } })
    end

    it 'should support searching through a month with provided time zone' do
      parsed = parse('created_at:2015-04-03:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00-03:00'.to_time,
        lt:  '2015-05-01T00:00:00-03:00'.to_time
      } } })
    end

    it 'should support searching through a day' do
      parsed = parse('created_at:2015-04-01',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00Z'.to_time,
        lt:  '2015-04-02T00:00:00Z'.to_time
      } } })
    end

    it 'should support searching through a day with provided time zone' do
      parsed = parse('created_at:2015-04-01+08:00',
                      allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00+08:00'.to_time,
        lt:  '2015-04-02T00:00:00+08:00'.to_time
      } } })
    end

    it 'should support searching through an hour' do
      parsed = parse('created_at:2015-04-01 01',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T01:00:00Z'.to_time,
        lt:  '2015-04-01T02:00:00Z'.to_time
      } } })
    end

    it 'should support searching through an hour with provided time zone' do
      parsed = parse('created_at:2015-04-01 01-04:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T01:00:00-04:00'.to_time,
        lt:  '2015-04-01T02:00:00-04:00'.to_time
      } } })
    end

    it 'should support searching through a minute' do
      parsed = parse('created_at:2015-04-01 01:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T01:00:00Z'.to_time,
        lt:  '2015-04-01T01:01:00Z'.to_time
      } } })
    end

    it 'should support searching through a minute with provided time zone' do
      parsed = parse('created_at:2015-04-01 01:00-04:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T01:00:00-04:00'.to_time,
        lt:  '2015-04-01T01:01:00-04:00'.to_time
      } } })
    end

    it 'should support searching through a second' do
      parsed = parse('created_at:2015-04-01 00:00:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00Z'.to_time,
        lt:  '2015-04-01T00:00:01Z'.to_time
      } } })
    end

    it 'should support searching through a second with provided time zone' do
      parsed = parse('created_at:2015-04-01 00:00:00+08:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-04-01T00:00:00+08:00'.to_time,
        lt:  '2015-04-01T00:00:01+08:00'.to_time
      } } })
    end

    it 'should carry over overflow in time units for upper time boundaries' do
      parsed = parse('created_at:2015-12-31 23:59:59+08:00',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: {
        gte: '2015-12-31T23:59:59+08:00'.to_time,
        lt:  '2016-01-01T00:00:00+08:00'.to_time
      } } })
    end

    it 'should search through an explicit year range' do
      parsed = parse('created_at.lt:2015',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: { lt: '2015-01-01T00:00:00Z'.to_time } } })
    end

    it 'should search through a precise date range' do
      parsed = parse('created_at.gte:2015-03-31T23:13:12',
                     allowed_fields: { date: [:created_at] })

      expect(parsed).to eq({ range: { created_at: { gte: '2015-03-31T23:13:12Z'.to_time } } })
    end
  end
end