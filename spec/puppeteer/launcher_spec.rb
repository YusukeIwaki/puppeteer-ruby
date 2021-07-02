require 'spec_helper'

RSpec.describe Puppeteer::Launcher do
  before { skip unless Puppeteer.env.darwin? }
  let(:instance) {
    Puppeteer::Launcher.new(
      project_root: '/tmp',
      preferred_revision: 'latest',
      is_puppeteer_core: true,
      product: product,
    )
  }

  describe 'executable_path' do
    subject { instance.executable_path(channel: channel) }

    context 'chrome' do
      let(:product) { 'chrome' }

      context 'without channel param' do
        subject { instance.executable_path }

        it { is_expected.to eq('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') }
      end

      context 'with invalid channel param' do
        let(:channel) { 'hoge' }

        it 'raises ArgumentError' do
          expect { subject }.to raise_error(/Allowed channel is \["chrome", "chrome-beta", "chrome-canary", "chrome-dev", "msedge"\]/)
        end
      end

      context 'with channel: chrome' do
        let(:channel) { :chrome }

        it { is_expected.to eq('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') }
      end

      context 'with channel: chrome-canary' do
        let(:channel) { 'chrome-canary' }

        it { is_expected.to eq('/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary') }
      end
    end

    context 'firefox' do
      let(:product) { 'firefox' }

      context 'without channel param' do
        subject { instance.executable_path }
      end

      context 'with invalid channel param' do
        let(:channel) { 'hoge' }

        it 'raises ArgumentError' do
          expect { subject }.to raise_error(/\["firefox", "firefox-nightly", "nightly"\]/)
        end
      end

      context 'with channel: nightly' do
        let(:channel) { 'nightly' }

        it { is_expected.to eq('/Applications/Firefox Nightly.app/Contents/MacOS/firefox') }
      end
    end
  end
end
