# rbs_inline: enabled

class Puppeteer::Dialog
  # @rbs type: String -- Dialog type
  # @rbs message: String -- Dialog message
  # @rbs default_value: String? -- Default prompt value, if any
  # @rbs return: void -- No return value
  def initialize(type:, message:, default_value: '')
    @type = type
    @message = message
    @default_value = default_value || ''
    @handled = false
  end

  attr_reader :type #: String
  attr_reader :message #: String
  attr_reader :default_value #: String

  # @rbs prompt_text: String? -- Text entered into the prompt
  # @rbs return: void -- No return value
  def accept(prompt_text = nil)
    if @handled
      raise 'Cannot accept dialog which is already handled!'
    end
    @handled = true
    handle(accept: true, text: prompt_text)
  end

  # @rbs return: void -- No return value
  def dismiss
    if @handled
      raise 'Cannot dismiss dialog which is already handled!'
    end
    @handled = true
    handle(accept: false)
  end

  # @rbs accept: bool -- Whether to accept the dialog
  # @rbs text: String? -- Text entered into the prompt
  # @rbs return: void -- No return value
  protected def handle(accept:, text: nil)
    raise NotImplementedError
  end
end

class Puppeteer::CdpDialog < Puppeteer::Dialog
  # @rbs client: Puppeteer::CDPSession -- CDP session used to handle dialog
  # @rbs type: String -- Dialog type
  # @rbs message: String -- Dialog message
  # @rbs default_value: String? -- Default prompt value, if any
  # @rbs return: void -- No return value
  def initialize(client, type:, message:, default_value:)
    super(type: type, message: message, default_value: default_value)
    @client = client
  end

  # @rbs accept: bool -- Whether to accept the dialog
  # @rbs text: String? -- Text entered into the prompt
  # @rbs return: void -- No return value
  protected def handle(accept:, text: nil)
    @client.send_message('Page.handleJavaScriptDialog', {
      accept: accept,
      promptText: text,
    }.compact)
    nil
  end
end
