KEYWORDS = %i[
  product
  channel
  executable_path
  ignore_default_args
  handle_SIGINT
  handle_SIGTERM
  handle_SIGHUP
  timeout
  dumpio
  env
  pipe
  extra_prefs_firefox
  args
  user_data_dir
  devtools
  debugging_port
  headless
  ignore_https_errors
  default_viewport
  slow_mo
]

RSpec.describe Puppeteer do
  it 'has a version number' do
    expect(Puppeteer::VERSION).not_to be nil
  end

  describe '#launch' do
    it 'returns an instance of Browser' do
      expect(Puppeteer.launch).to be_a(Puppeteer::Browser)
    end

    KEYWORDS.each do |keyword|
      it "returns an instance of Browser if instantiated with the :#{keyword} kwarg" do
        expect(Puppeteer.launch(**{ keyword => nil })).to be_a(Puppeteer::Browser)
      end
    end
  end
end
