RSpec.describe Puppeteer do
  it 'has a version number' do
    expect(Puppeteer::VERSION).not_to be nil
  end

  describe '#launch' do
    it 'returns an instance of Browser' do
      expect(Puppeteer.launch).to be_a(Puppeteer::Browser)
    end
  end
end
