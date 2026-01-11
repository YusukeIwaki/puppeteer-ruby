require 'spec_helper'

RSpec.describe 'Input (white-box / Ruby-specific)' do
  it 'dispatches cancel event when FileChooser is canceled' do
    with_test_state do |page:, **|
      page.content = '<input type=file>'
      page.evaluate(<<~JAVASCRIPT)
      () => {
        const input = document.querySelector('input');
        globalThis.cancelEventFired = false;
        input.addEventListener('cancel', () => {
          globalThis.cancelEventFired = true;
        });
      }
      JAVASCRIPT

      chooser = page.wait_for_file_chooser do
        page.click('input')
      end
      chooser.cancel

      expect(page.evaluate('() => globalThis.cancelEventFired')).to eq(true)
    end
  end
end
