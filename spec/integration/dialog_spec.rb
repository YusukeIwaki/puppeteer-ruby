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
end
