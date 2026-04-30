require 'spec_helper'

RSpec.describe Puppeteer::ChromeUserDataDir do
  describe '.resolve_default' do
    it 'resolves macOS default user data dirs' do
      expect(described_class.resolve_default('chrome', platform: :darwin, home: '/Users/alice')).to eq(
        '/Users/alice/Library/Application Support/Google/Chrome',
      )
      expect(described_class.resolve_default(:'chrome-canary', platform: :darwin, home: '/Users/alice')).to eq(
        '/Users/alice/Library/Application Support/Google/Chrome Canary',
      )
    end

    it 'resolves Linux default user data dirs' do
      expect(
        described_class.resolve_default('chrome-dev', platform: :linux, env: { 'CHROME_CONFIG_HOME' => '/chrome-config' }, home: '/home/alice'),
      ).to eq('/chrome-config/google-chrome-unstable')
      expect(
        described_class.resolve_default('chrome-beta', platform: :linux, env: { 'XDG_CONFIG_HOME' => '/xdg-config' }, home: '/home/alice'),
      ).to eq('/xdg-config/google-chrome-beta')
      expect(described_class.resolve_default('chrome', platform: :linux, env: {}, home: '/home/alice')).to eq(
        '/home/alice/.config/google-chrome',
      )
    end

    it 'resolves Windows default user data dirs' do
      expect(
        described_class.resolve_default('chrome', platform: :windows, env: { 'LOCALAPPDATA' => 'C:\Users\alice\AppData\Local' }, home: 'C:\Users\alice'),
      ).to eq('C:\Users\alice\AppData\Local\Google\Chrome\User Data')
      expect(described_class.resolve_default('chrome-dev', platform: :windows, env: {}, home: 'C:\Users\alice')).to eq(
        'C:\Users\alice\AppData\Local\Google\Chrome Dev\User Data',
      )
    end

    it 'rejects unknown channels' do
      expect {
        described_class.resolve_default('msedge', platform: :darwin, home: '/Users/alice')
      }.to raise_error(ArgumentError, /Invalid channel: 'msedge'/)
    end
  end
end
