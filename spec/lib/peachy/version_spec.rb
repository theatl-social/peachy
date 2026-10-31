# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Peachy::Version do
  describe '.to_s' do
    it 'returns the major, minor and patch version joined by dots' do
      expect(described_class.to_s).to eq('0.1.0')
    end
  end

  describe '.to_a' do
    it 'returns the version components' do
      expect(described_class.to_a).to eq([0, 1, 0])
    end
  end
end
