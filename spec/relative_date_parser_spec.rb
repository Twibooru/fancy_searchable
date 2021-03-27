require 'rspec'
require 'fancy_searchable/relative_date_parser'

RSpec.describe FancySearchable::RelativeDateParser do
  before(:all) do
    @origin = Time.new(2021, 3, 26, 21, 30, 00)
  end

  def parse(input)
    FancySearchable::RelativeDateParser.parse input, @origin
  end

  it 'should not parse an invalid date' do
    expect(parse('foo bar baz')).to be_nil
  end

  describe 'seconds' do
    it 'should parse a second' do
      higher, lower = parse('1 second ago')

      expect(@origin - higher).to eq 1
    end

    it 'should parse multiple seconds' do
      higher, lower = parse('10 seconds ago')

      expect(@origin - higher).to eq 10
    end
  end

  describe 'minutes' do
    it 'should parse a minute' do
      higher, lower = parse('1 minute ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_MINUTE
    end

    it 'should parse multiple minutes' do
      higher, lower = parse('10 minutes ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_MINUTE * 10
    end
  end

  describe 'hours' do
    it 'should parse an hour' do
      higher, lower = parse('1 hour ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_HOUR
    end

    it 'should parse multiple hours' do
      higher, lower = parse('10 hours ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_HOUR * 10
    end
  end

  describe 'days' do
    it 'should parse a day' do
      higher, = parse('1 day ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_DAY
    end

    it 'should parse multiple days' do
      higher, = parse('10 days ago')

      expect(@origin - higher).to eq ActiveSupport::Duration::SECONDS_PER_DAY * 10
    end
  end

  describe 'weeks' do
    it 'should parse a week' do
      higher, = parse('1 week ago')

      expect(@origin - higher).to eq 604800
    end

    it 'should parse multiple weeks' do
      expect(parse('10 weeks ago')).to_not be_nil
    end
  end

  # Assume it works for months and years because those are a little more variable
  it 'should return non nil for a month' do
    expect(parse('1 month ago')).to_not be_nil
  end

  it 'should return non nil for a year' do
    expect(parse('1 year ago')).to_not be_nil
  end
end