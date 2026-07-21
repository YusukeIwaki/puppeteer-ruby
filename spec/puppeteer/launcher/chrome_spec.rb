require 'spec_helper'

RSpec.describe Puppeteer::Launcher::Chrome do
  describe '.get_features' do
    it 'returns an empty array when no options are provided' do
      result = described_class.get_features('--foo')
      expect(result).to eq([])
    end

    it 'returns an empty array when no options match the flag' do
      result = described_class.get_features('--foo', ['--bar', '--baz'])
      expect(result).to eq([])
    end

    it 'returns an array of values when options match the flag' do
      result = described_class.get_features('--foo', ['--foo=bar', '--foo=baz'])
      expect(result).to eq(['bar', 'baz'])
    end

    it 'does not handle whitespace' do
      result = described_class.get_features('--foo', ['--foo bar', '--foo baz '])
      expect(result).to eq([])
    end

    it 'handles equals sign around the flag and value' do
      result = described_class.get_features('--foo', ['--foo=bar', '--foo=baz '])
      expect(result).to eq(['bar', 'baz'])
    end

    it 'handles comma-separated values' do
      result = described_class.get_features('--foo', ['--foo=bar,baz', '--foo=qux'])
      expect(result).to eq(['bar', 'baz', 'qux'])
    end
  end

  describe '.remove_matching_flags' do
    it 'empty' do
      values = []
      expect(described_class.remove_matching_flags(values, '--foo')).to eq([])
    end

    it 'with one match' do
      values = ['--foo=1', '--bar=baz']
      expect(described_class.remove_matching_flags(values, '--foo')).to eq(['--bar=baz'])
    end

    it 'with multiple matches' do
      values = ['--foo=1', '--foo=2', '--bar=baz']
      expect(described_class.remove_matching_flags(values, '--foo')).to eq(['--bar=baz'])
    end

    it 'with no matches' do
      values = ['--foo=1', '--bar=baz']
      expect(described_class.remove_matching_flags(values, '--baz')).to eq(['--foo=1', '--bar=baz'])
    end
  end

  describe 'ChromeLauncher' do
    it 'removes disabled features if they are enabled explicitly' do
      launcher = described_class.new(
        project_root: nil,
        preferred_revision: nil,
        is_puppeteer_core: true,
      )
      args = launcher.default_args(args: ['--enable-features=Translate']).to_a
      disable_features_flag = args.find { |arg| arg.start_with?('--disable-features=') }
      expect(disable_features_flag).to be_truthy
      disabled_features = disable_features_flag.split('=')[1].split(',')
      expect(disabled_features).not_to include('Translate')
    end
  end
end
