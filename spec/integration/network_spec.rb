require 'spec_helper'

RSpec.describe 'network' do
  describe 'Request.initiator', skip: Puppeteer.env.firefox? do
    it 'shoud return the initiator', sinatra: true do
      initiators = {}
      page.on('request') do |req|
        initiators[req.url.split('/').last] = req.initiator
      end
      page.goto("#{server_prefix}/initiator.html")

      expect(initiators['initiator.html']).to include({ 'type' => 'other' })
      expect(initiators['initiator.js']).to include({
        'type' => 'parser',
        'url' => "#{server_prefix}/initiator.html",
      })
      expect(initiators['frame.html']).to include({
        'type' => 'parser',
        'url' => "#{server_prefix}/initiator.html",
      })
      expect(initiators['script.js']).to include({
        'type' => 'parser',
        'url' => "#{server_prefix}/frames/frame.html",
      })
      expect(initiators['style.css']).to include({
        'type' => 'parser',
        'url' => "#{server_prefix}/frames/frame.html",
      })
      expect(initiators['initiator.js']).to include({
        'type' => 'parser',
        'url' => "#{server_prefix}/initiator.html",
      })
      expect(initiators['injectedfile.js']).to include({
        'type' => 'script',
        'stack' => include({
          'callFrames' => [
            include({ 'url' => "#{server_prefix}/initiator.js" }),
          ],
        }),
      })
      expect(initiators['injectedstyle.css']).to include({
        'type' => 'script',
        'stack' => include({
          'callFrames' => [
            include({ 'url' => "#{server_prefix}/initiator.js" }),
          ],
        }),
      })
    end
  end

  describe 'Response.statusText', sinatra: true do
    it 'should work' do
      sinatra.get('/cool') do
        status 201
        body 'It is cool'
      end

      response = page.goto("#{server_prefix}/cool")
      expect(response.status_text).to eq(Rack::Utils::HTTP_STATUS_CODES[201])
    end
  end
end
