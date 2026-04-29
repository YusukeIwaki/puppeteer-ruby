require 'test_helper'

describe 'Autofill' do
  it 'should fill out a credit card', sinatra: true do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/credit-card.html")
      name = page.wait_for_selector('#name')
      name.autofill(
        credit_card: {
          number: '4444444444444444',
          name: 'John Smith',
          expiryMonth: '01',
          expiryYear: '2030',
          cvc: '123',
        },
      )

      values = page.evaluate(<<~JAVASCRIPT)
        () => {
          const result = [];
          for (const el of document.querySelectorAll('input')) {
            result.push(el.value);
          }
          return result.join(',');
        }
      JAVASCRIPT
      expect(values).to eq('John Smith,4444444444444444,01,2030,Submit')
    end
  end

  it 'should fill out an address', sinatra: true do
    with_test_state do |page:, server:, **|
      page.goto("#{server.prefix}/address.html")
      name = page.wait_for_selector('#name')
      name.autofill(
        address: {
          fields: [
            { name: 'NAME_FULL', value: 'Jane Doe' },
            { name: 'ADDRESS_HOME_STREET_ADDRESS', value: '123 Main St' },
            { name: 'ADDRESS_HOME_CITY', value: 'Anytown' },
            { name: 'ADDRESS_HOME_ZIP', value: '12345' },
          ],
        },
      )

      values = page.evaluate(<<~JAVASCRIPT)
        () => {
          const result = [];
          for (const el of document.querySelectorAll('input')) {
            result.push(el.value);
          }
          return result.join(',');
        }
      JAVASCRIPT
      expect(values).to eq('Jane Doe,123 Main St,Anytown,12345,Submit')
    end
  end
end
