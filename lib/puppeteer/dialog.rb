class Puppeteer::Dialog
  def initialize(client, type, message, default_value)
    @client = client
    @type = type
    @message = message
    @default_value = default_value || ''
  end

  attr_reader :type, :message, :default_value

  # @param prompt_text - optional text that will be entered in the dialog
  # prompt. Has no effect if the dialog's type is not `prompt`.
  #
  # @returns A promise that resolves when the dialog has been accepted.
  def accept(prompt_text = nil)
    if @handled
      raise 'Cannot accept dialog which is already handled!'
    end
    @handled = true
    @client.send_message('Page.handleJavaScriptDialog', {
      accept: true,
      promptText: prompt_text,
    }.compact)
  end

  # @returns A promise which will resolve once the dialog has been dismissed
  def dismiss
    if @handled
      raise 'Cannot accept dialog which is already handled!'
    end
    @handled = true
    @client.send_message('Page.handleJavaScriptDialog', accept: false)
  end
end
