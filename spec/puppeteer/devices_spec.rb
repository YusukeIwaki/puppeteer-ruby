require 'spec_helper'

RSpec.describe Puppeteer::Devices do
  it {
    expect(described_class.iPhone_XR.viewport.width).to eq(414)
    expect(described_class.Kindle_Fire_HDX.viewport.landscape?).to eq(false)
    expect(described_class.Microsoft_Lumia_550.user_agent).to eq('Mozilla/5.0 (Windows Phone 10.0; Android 4.2.1; Microsoft; Lumia 550) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Mobile Safari/537.36 Edge/14.14263')
  }

  it 'includes current iPhone descriptors (upstream #15400)' do
    se = described_class.iPhone_SE__3rd_gen_
    expect(se.viewport.width).to eq(375)
    expect(se.viewport.height).to eq(667)
    expect(se.user_agent).to include('iPhone OS 18_5')

    pro = described_class.iPhone_17_Pro
    expect(pro.viewport.width).to eq(402)
    expect(pro.viewport.height).to eq(681)
    expect(pro.viewport.device_scale_factor).to eq(3)

    pro_max_landscape = described_class.iPhone_17_Pro_Max_landscape
    expect(pro_max_landscape.viewport.width).to eq(838)
    expect(pro_max_landscape.viewport.height).to eq(390)
    expect(pro_max_landscape.viewport.landscape?).to eq(true)

    air = described_class.iPhone_Air
    expect(air.viewport.width).to eq(420)
    expect(air.viewport.height).to eq(719)

    e = described_class.iPhone_16e
    expect(e.viewport.width).to eq(390)
    expect(e.viewport.height).to eq(651)
  end
end
