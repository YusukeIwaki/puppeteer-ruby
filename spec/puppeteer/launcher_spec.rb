require 'spec_helper'

RSpec.describe Puppeteer::Launcher do
  let(:instance) {
    Puppeteer::Launcher.new(
      project_root: '/tmp',
      preferred_revision: 'latest',
      is_puppeteer_core: true,
      product: product,
    )
  }

  describe 'executable_path' do
    before { skip unless Puppeteer.env.darwin? }

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
  end

  describe 'executable_path detection' do
    before {
      skip if Puppeteer.env.windows? || Puppeteer.env.darwin?
    }

    subject { instance.executable_path(channel: channel) }

    context 'chrome' do
      let(:product) { 'chrome' }

      context 'path finder cannot find chrome' do
        subject { instance.executable_path }
        before {
          allow_any_instance_of(Puppeteer::ExecutablePathFinder).to receive(:find_first).and_return(nil)
        }

        it { expect { subject }.to raise_error(/chrome is not installed on this system.\nExpected path/) }
      end

      context 'path finder find chrome' do
        subject { instance.executable_path }
        before {
          allow_any_instance_of(Puppeteer::ExecutablePathFinder).to receive(:find_first).and_return('./unknown')
        }

        it { expect { subject }.to raise_error(/chrome is not installed on this system.\nExpected path: .\/unknown/) }
      end
    end
  end
end
