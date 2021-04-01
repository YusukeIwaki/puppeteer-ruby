require 'json'

class Puppeteer::Connection
  include Puppeteer::DebugPrint
  include Puppeteer::EventCallbackable
  using Puppeteer::DefineAsyncMethod

  class ProtocolError < StandardError
    def initialize(method:, error_message:, error_data: nil)
      msg = "Protocol error (#{method}): #{error_message}"
      if error_data
        super("#{msg} #{error_data}")
      else
        super(msg)
      end
    end
  end

  # callback object stored in @callbacks.
  class MessageCallback
    # @param method [String]
    # @param promise [Concurrent::Promises::ResolvableFuture]
    def initialize(method:, promise:)
      @method = method
      @promise = promise
    end

    def resolve(result)
      @promise.fulfill(result)
    end

    def reject(error)
      @promise.reject(error)
    end

    attr_reader :method
  end

  def initialize(url, transport, delay = 0)
    @url = url
    @last_id = 0
    @callbacks = Concurrent::Hash.new
    @delay = delay

    @transport = transport
    @transport.on_message do |data|
      message = JSON.parse(data)
      if can_handle_async?(message)
        async_handle_message(message)
      else
        handle_message(message)
      end
    end
    @transport.on_close do |reason, code|
      handle_close
    end

    @sessions = Concurrent::Hash.new
    @closed = false
  end

  # used only in Browser#connected?
  def closed?
    @closed
  end

  private def can_handle_async?(message)
    return true unless message['method']

    # Puppeteer doesn't handle any Network monitoring responses.
    # So we don't care their handling order.
    message['method'].start_with?('Network.')
  end

  def self.from_session(session)
    session.connection
  end

  # @param {string} sessionId
  # @return {?CDPSession}
  def session(session_id)
    @sessions[session_id]
  end

  def url
    @url
  end

  # @param {string} method
  # @param {!Object=} params
  def send_message(method, params = {})
    await async_send_message(method, params)
  end

  def async_send_message(method, params = {})
    promise = resolvable_future

    generate_id do |id|
      @callbacks[id] = MessageCallback.new(method: method, promise: promise)
      raw_send(id: id, message: { method: method, params: params })
    end

    promise
  end

  # package private. not intended to use externally.
  #
  # ```usage
  # connection.generate_id do |generated_id|
  #   # play with generated_id
  # end
  # ````
  #
  def generate_id(&block)
    block.call(@last_id += 1)
  end

  # package private. not intended to use externally.
  def raw_send(id:, message:)
    # In original puppeteer (JS) implementation,
    # id is generated here using #generate_id and the id argument is not passed to #raw_send.
    #
    # However with concurrent-ruby, '#handle_message' is sometimes called
    # just soon after @transport.send_text and **before returning the id.**
    #
    # So we have to know the message id in advance before send_text.
    #
    payload = JSON.fast_generate(message.compact.merge(id: id))
    @transport.send_text(payload)
    request_debug_printer.handle_payload(payload)
  end

  # Just for effective debugging :)
  class RequestDebugPrinter
    include Puppeteer::DebugPrint

    def handle_payload(payload)
      debug_puts "SEND >> #{decorate(payload)}"
    end

    private def decorate(payload)
      payload.gsub(/"method":"([^"]+)"/, "\"method\":\"\u001b[32m\\1\u001b[0m\"")
    end
  end

  class ResponseDebugPrinter
    include Puppeteer::DebugPrint

    NON_DEBUG_PRINT_METHODS = [
      'Network.dataReceived',
      'Network.loadingFinished',
      'Network.requestWillBeSent',
      'Network.requestWillBeSentExtraInfo',
      'Network.responseReceived',
      'Network.responseReceivedExtraInfo',
      'Page.lifecycleEvent',
    ]

    def handle_message(message)
      if skip_debug_print?(message['method'])
        debug_print '.'
        @prev_log_skipped = true
      else
        debug_print "\n" if @prev_log_skipped
        @prev_log_skipped = nil
        debug_puts "RECV << #{decorate(message)}"
      end
    end

    private def skip_debug_print?(method)
      method && NON_DEBUG_PRINT_METHODS.include?(method)
    end

    private def decorate(message)
      # decorate RED for error.
      if message['error']
        return "\u001b[31m#{message}\u001b[0m"
      end

      # ignore method call response, or with no method.
      return message if message['id'] || !message['method']

      # decorate cyan for method name.
      message.to_s.gsub(message['method'], "\u001b[36m#{message['method']}\u001b[0m")
    end
  end

  private def request_debug_printer
    @request_debug_printer ||= RequestDebugPrinter.new
  end

  private def response_debug_printer
    @response_debug_printer ||= ResponseDebugPrinter.new
  end

  private def handle_message(message)
    if @delay > 0
      sleep(@delay / 1000.0)
    end

    response_debug_printer.handle_message(message)

    case message['method']
    when 'Target.attachedToTarget'
      session_id = message['params']['sessionId']
      session = Puppeteer::CDPSession.new(self, message['params']['targetInfo']['type'], session_id)
      @sessions[session_id] = session
    when 'Target.detachedFromTarget'
      session_id = message['params']['sessionId']
      session = @sessions[session_id]
      if session
        session.handle_closed
        @sessions.delete(session_id)
      end
    end

    if message['sessionId']
      session_id = message['sessionId']
      @sessions[session_id]&.handle_message(message)
    elsif message['id']
      # Callbacks could be all rejected if someone has called `.dispose()`.
      if callback = @callbacks.delete(message['id'])
        if message['error']
          callback.reject(
            ProtocolError.new(
              method: callback.method,
              error_message: message['error']['message'],
              error_data: message['error']['data']))
        else
          callback.resolve(message['result'])
        end
      end
    else
      future { emit_event(message['method'], message['params']) }
    end
  end

  private define_async_method :async_handle_message

  private def handle_close
    return if @closed
    @closed = true
    @transport.on_message
    @transport.on_close
    @callbacks.each_value do |callback|
      callback.reject(
        ProtocolError.new(
          method: callback.method,
          error_message: 'Target Closed.'))
    end
    @callbacks.clear
    @sessions.each_value do |session|
      session.handle_closed
    end
    @sessions.clear
    emit_event(ConnectionEmittedEvents::Disconnected)
  end

  def on_close(&block)
    @on_close = block
  end

  def on_message(&block)
    @on_message = block
  end

  def dispose
    handle_close
    @transport.close
  end

  # @param {Protocol.Target.TargetInfo} targetInfo
  # @return [CDPSession]
  def create_session(target_info)
    result = send_message('Target.attachToTarget', targetId: target_info.target_id, flatten: true)
    session_id = result['sessionId']
    @sessions[session_id]
  end
end
