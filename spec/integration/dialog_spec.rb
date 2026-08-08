require 'spec_helper'

RSpec.describe 'Page.Events.Dialog' do
  it 'should fire' do
    with_test_state do |page:, **|
      dialog_calls = []

      page.on('dialog') do |dialog|
        dialog_calls << dialog
        dialog.accept
      end
      page.evaluate("() => alert('yo')")

      expect(dialog_calls.length).to eq(1)
      dialog = dialog_calls.first
      expect(dialog.type).to eq('alert')
      expect(dialog.default_value).to eq('')
      expect(dialog.message).to eq('yo')
    end
  end

  it 'should allow accepting prompts' do
    with_test_state do |page:, **|
      dialog_calls = []

      page.on('dialog') do |dialog|
        dialog_calls << dialog
        dialog.accept('answer!')
      end

      result = page.evaluate("() => prompt('question?', 'yes.')")

      expect(dialog_calls.length).to eq(1)
      dialog = dialog_calls.first
      expect(dialog.type).to eq('prompt')
      expect(dialog.default_value).to eq('yes.')
      expect(dialog.message).to eq('question?')
      expect(result).to eq('answer!')
    end
  end

  it 'should dismiss the prompt' do
    with_test_state do |page:, **|
      page.on('dialog') do |dialog|
        dialog.dismiss
      end

      result = page.evaluate("() => prompt('question?')")
      expect(result).to be_nil
    end
  end

  it 'should see dialogs handled by other connections' do
    with_test_state do |page:, server:, browser:, **|
      page.goto(server.empty_page)

      Puppeteer.connect(browser_ws_endpoint: browser.ws_endpoint) do |browser2|
        page2 = browser2.pages.find { |candidate| candidate.url == server.empty_page }
        raise 'Could not find page2' unless page2

        dialog1_promise = Async::Promise.new
        page.once('dialog') { |dialog| dialog1_promise.resolve(dialog) }
        dialog2_promise = Async::Promise.new
        page2.once('dialog') { |dialog| dialog2_promise.resolve(dialog) }

        evaluate_promise = async_promise do
          page2.evaluate("() => prompt('question?', 'yes.')")
        end

        dialog1 = dialog1_promise.wait
        dialog2 = dialog2_promise.wait

        dialog2.accept('answer!')

        result = evaluate_promise.wait
        expect(result).to eq('answer!')

        # Wait for the event to be processed by the first connection.
        page.evaluate('() => 1')

        expect(dialog1.handled?).to eq(true)
        expect(dialog2.handled?).to eq(true)
      end
    end
  end

  it 'should expose whether the dialog has been handled' do
    with_test_state do |page:, **|
      handled_states = []
      page.on('dialog') do |dialog|
        handled_states << dialog.handled?
        dialog.dismiss
        handled_states << dialog.handled?
      end

      page.evaluate("() => alert('yo')")
      expect(handled_states).to eq([false, true])
    end
  end
end
