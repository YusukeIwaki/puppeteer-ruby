require 'spec_helper'

RSpec.describe Puppeteer::Devices do
  it {
    expect(described_class.iPhone_XR.viewport.width).to eq(414)
    expect(described_class.Kindle_Fire_HDX.viewport.landscape?).to eq(false)
    expect(described_class.Microsoft_Lumia_550.user_agent).to eq('Mozilla/5.0 (Windows Phone 10.0; Android 4.2.1; Microsoft; Lumia 550) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Mobile Safari/537.36 Edge/14.14263')
  }
end
