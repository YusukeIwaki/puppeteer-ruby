require 'spec_helper'
require 'tmpdir'

RSpec.describe Puppeteer::FileSystem do
  def with_protected_policy
    skip('Symlinks require privileges on Windows') if Puppeteer.env.windows?
    Puppeteer.set_follow_symlinks(false)
    begin
      yield
    ensure
      Puppeteer.set_follow_symlinks(true)
    end
  end

  it 'creates protected exclusive output with mode 0600' do
    with_protected_policy do
      Dir.mktmpdir('puppeteer-fs-') do |directory|
        path = File.join(directory, 'recording.mp4')
        file = described_class.open_exclusive(path)
        file.close
        expect(File.stat(path).mode & 0o777).to eq(0o600)
      end
    end
  end

  it 'rejects exclusive creation when the file exists' do
    with_protected_policy do
      Dir.mktmpdir('puppeteer-fs-') do |directory|
        path = File.join(directory, 'existing.mp4')
        File.binwrite(path, 'placeholder')
        expect { described_class.open_exclusive(path) }.to raise_error(Errno::EEXIST)
        expect(File.binread(path)).to eq('placeholder')
      end
    end
  end

end
