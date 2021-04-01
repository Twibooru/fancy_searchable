require 'rspec'
require 'fancy_searchable'

RSpec.describe FancySearchable::Parsing::SearchLexer do
  def lex(input)
    FancySearchable::Parsing::SearchLexer.lex input
  end

  describe 'individual terms' do
    it 'should lex a basic term' do
      expect(lex('ts')).to eq ['ts']
    end

    it 'should lex a term with spaces in it' do
      expect(lex('twilight sparkle')).to eq ['twilight sparkle']
    end

    it 'should lex a term with parentheses in it' do
      expect(lex('twilight sparkle (alicorn)')).to eq ['twilight sparkle (alicorn)']
      expect(lex(':(')).to eq [':(']
    end

    it 'should lex a term with something that looks like a NOT operator in it' do
      expect(lex('sci-twi')).to eq ['sci-twi']
      expect(lex('panic! at the disco')).to eq ['panic! at the disco']
      expect(lex('why !would you want to do this')).to eq ['why !would you want to do this']
    end
  end

  describe 'prefix operators' do
    it 'should lex a NOT operator' do
      expect(lex('!pp')).to eq ['pp', :not_op]
      expect(lex('-pp')).to eq ['pp', :not_op]
      expect(lex('NOT pp')).to eq ['pp', :not_op]
    end

    it 'should lex a not operator with spaces' do
      expect(lex('!pinkie pie')).to eq ['pinkie pie', :not_op]
      expect(lex('-pinkie pie')).to eq ['pinkie pie', :not_op]
      expect(lex('NOT pinkie pie')).to eq ['pinkie pie', :not_op]
    end
  end

  describe 'infix operators' do
    it 'should lex an OR operator' do
      expect(lex('sg OR ts')).to eq ['sg', 'ts', :or_op]
      expect(lex('sg || ts')).to eq ['sg', 'ts', :or_op]
    end

    it 'should lex an OR operator with spaces' do
      expect(lex('starlight glimmer OR twilight sparkle')).to eq ['starlight glimmer', 'twilight sparkle', :or_op]
      expect(lex('starlight glimmer || twilight sparkle')).to eq ['starlight glimmer', 'twilight sparkle', :or_op]
    end

    it 'should lex an AND operator' do
      expect(lex('sg AND ts')).to eq ['sg', 'ts', :and_op]
      expect(lex('sg && ts')).to eq ['sg', 'ts', :and_op]
      expect(lex('sg,ts')).to eq ['sg', 'ts', :and_op]
    end

    it 'should lex an AND operator with spaces' do
      expect(lex('starlight glimmer AND twilight sparkle')).to eq ['starlight glimmer', 'twilight sparkle', :and_op]
      expect(lex('starlight glimmer && twilight sparkle')).to eq ['starlight glimmer', 'twilight sparkle', :and_op]
      expect(lex('starlight glimmer, twilight sparkle')).to eq ['starlight glimmer', 'twilight sparkle', :and_op]
    end

    it 'should lex an OR operator with one of the operands being NOTed' do
      expect(lex('!fluttershy || twilight sparkle')).to eq ['fluttershy', :not_op, 'twilight sparkle', :or_op]
    end
  end

  describe 'grouping' do
    it 'should lex parenthesized subexpressions' do
      expect(lex('pp || (sg && ts)')).to eq ['pp', 'sg', 'ts', :and_op, :or_op]
    end

    it 'should ensure parentheses are balanced' do
      expect { lex('(') }.to raise_error FancySearchable::Parsing::SearchLexingError
      expect { lex('pp || (sg && ts') }.to raise_error FancySearchable::Parsing::SearchLexingError
    end
  end
end