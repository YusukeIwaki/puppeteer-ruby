require 'spec_helper'

RSpec.describe 'Page.Events.Dialog' do
  include_context 'with test state'
  it 'should fire' do
    my_dialog = nil

    page.on('dialog') do |dialog|
      my_dialog = dialog
      dialog.accept
    end
    page.evaluate("() => alert('yo')")

    expect(my_dialog.type).to eq('alert')
    expect(my_dialog.default_value).to eq('')
    expect(my_dialog.message).to eq("yo")
  end

  it 'should allow accepting prompts' do
    my_dialog = nil

    page.on('dialog') do |dialog|
      my_dialog = dialog
      dialog.accept('answer!')
    end
    result = page.evaluate("() => prompt('question?', 'yes.')")

    expect(my_dialog.type).to eq('prompt')
    expect(my_dialog.default_value).to eq('yes.')
    expect(my_dialog.message).to eq('question?')
    expect(result).to eq('answer!')
  end

  it 'should dismiss accepting prompts' do
    my_dialog = nil

    page.on('dialog') do |dialog|
      my_dialog = dialog
      dialog.dismiss
    end
    result = page.evaluate("() => prompt('question?')")

    expect(result).to be_nil
  end
end
