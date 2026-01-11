class Puppeteer::FileChooser
  # @param element [Puppeteer::ElementHandle]
  # @param event [Hash]
  def initialize(element, event)
    @element = element
    @multiple = event['mode'] != 'selectSingle'
    @handled = false
  end

  def multiple?
    @multiple
  end

  # @param file_paths [Array<String>]
  def accept(file_paths)
    if @handled
      raise 'Cannot accept FileChooser which is already handled!'
    end
    @handled = true
    @element.upload_file(*file_paths)
  end

  def cancel
    if @handled
      raise 'Cannot cancel FileChooser which is already handled!'
    end
    @handled = true
    js = <<~JAVASCRIPT
    (element) => {
      element.dispatchEvent(new Event('cancel', { bubbles: true }));
    }
    JAVASCRIPT
    @element.evaluate(js)
  end
end
