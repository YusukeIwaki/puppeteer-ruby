# rbs_inline: enabled

class Puppeteer::Frame
  using Puppeteer::DefineAsyncMethod

  # @rbs frame_manager: Puppeteer::FrameManager -- Owning frame manager
  # @rbs parent_frame: Puppeteer::Frame? -- Parent frame
  # @rbs frame_id: String -- Frame ID
  # @rbs client: Puppeteer::CDPSession -- CDP session
  # @rbs return: void -- No return value
  def initialize(frame_manager, parent_frame, frame_id, client)
    @frame_manager = frame_manager
    @parent_frame = parent_frame
    @id = frame_id
    @detached = false
    @has_started_loading = false

    @loader_id = ''
    @lifecycle_events = Set.new
    @child_frames = Set.new
    if parent_frame
      parent_frame._child_frames << self
    end

    update_client(client)
  end

  # @rbs return: untyped -- Result
  def inspect
    values = %i[id parent_frame detached loader_id lifecycle_events child_frames].map do |sym|
      value = instance_variable_get(:"@#{sym}")
      "@#{sym}=#{value}"
    end
    "#<Puppeteer::Frame #{values.join(' ')}>"
  end

  # @rbs return: untyped -- Result
  def _client
    @client
  end

  private def update_client(client)
    @client = client
    @main_world = Puppeteer::IsolaatedWorld.new(@client, @frame_manager, self, @frame_manager.timeout_settings)
    @puppeteer_world = Puppeteer::IsolaatedWorld.new(@client, @frame_manager, self, @frame_manager.timeout_settings)
  end

  # @rbs return: untyped -- Result
  def page
    @frame_manager.page
  end

  # @rbs return: untyped -- Result
  def oop_frame?
    @client != @frame_manager.client
  end

  attr_accessor :frame_manager, :id, :loader_id, :lifecycle_events, :main_world, :puppeteer_world

  # @rbs other: untyped -- other parameter
  # @rbs return: untyped -- Result
  def ==(other)
    other = other.__getobj__ if other.is_a?(Puppeteer::ReactorRunner::Proxy)
    return true if equal?(other)
    return false unless other.is_a?(Puppeteer::Frame)
    return false unless @id && other.id

    @id == other.id
  end

  # @rbs return: untyped -- Result
  def has_started_loading?
    @has_started_loading
  end

  # @rbs url: String -- URL to navigate
  # @rbs referer: String? -- Referer header value
  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String? -- Lifecycle event to wait for
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def goto(url, referer: nil, timeout: nil, wait_until: nil)
    @frame_manager.navigate_frame(self, url, referer: referer, timeout: timeout, wait_until: wait_until)
  end

  # @rbs timeout: Numeric? -- Navigation timeout in milliseconds
  # @rbs wait_until: String? -- Lifecycle event to wait for
  # @rbs return: Puppeteer::HTTPResponse? -- Navigation response
  def wait_for_navigation(timeout: nil, wait_until: nil)
    @frame_manager.wait_for_frame_navigation(self, timeout: timeout, wait_until: wait_until)
  end

  define_async_method :async_wait_for_navigation

  # @rbs return: untyped -- Result
  def execution_context
    @main_world.execution_context
  end

  # @rbs page_function: untyped -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: untyped -- Result
  def evaluate_handle(page_function, *args)
    @main_world.evaluate_handle(page_function, *args)
  end

  define_async_method :async_evaluate_handle

  # @rbs page_function: untyped -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: untyped -- Result
  def evaluate(page_function, *args)
    @main_world.evaluate(page_function, *args)
  end

  define_async_method :async_evaluate

  # `$()` in JavaScript.
  # @rbs selector: untyped -- selector parameter
  # @rbs return: untyped -- Result
  def query_selector(selector)
    @main_world.query_selector(selector)
  end
  alias_method :S, :query_selector

  define_async_method :async_query_selector

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @rbs expression: untyped -- expression parameter
  # @rbs return: untyped -- Result
  def Sx(expression)
    param_xpath =
      if expression.start_with?('//')
        ".#{expression}"
      else
        expression
      end

    query_selector_all("xpath/#{param_xpath}")
  end

  define_async_method :async_Sx

  # `$eval()` in JavaScript.
  # @rbs selector: untyped -- selector parameter
  # @rbs page_function: untyped -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: untyped -- Result
  def eval_on_selector(selector, page_function, *args)
    @main_world.eval_on_selector(selector, page_function, *args)
  end
  alias_method :Seval, :eval_on_selector

  define_async_method :async_eval_on_selector

  # `$$eval()` in JavaScript.
  # @rbs selector: untyped -- selector parameter
  # @rbs page_function: untyped -- page_function parameter
  # @rbs args: Array[untyped] -- args parameter
  # @rbs return: untyped -- Result
  def eval_on_selector_all(selector, page_function, *args)
    @main_world.eval_on_selector_all(selector, page_function, *args)
  end
  alias_method :SSeval, :eval_on_selector_all

  define_async_method :async_eval_on_selector_all

  # `$$()` in JavaScript.
  # @rbs selector: untyped -- selector parameter
  # @rbs return: untyped -- Result
  def query_selector_all(selector)
    @main_world.query_selector_all(selector)
  end
  alias_method :SS, :query_selector_all

  define_async_method :async_query_selector_all

  # @rbs return: untyped -- Result
  def content
    @puppeteer_world.content
  end

  # @rbs html: untyped -- html parameter
  # @rbs timeout: untyped -- timeout parameter
  # @rbs wait_until: untyped -- wait_until parameter
  # @rbs return: untyped -- Result
  def set_content(html, timeout: nil, wait_until: nil)
    @puppeteer_world.set_content(html, timeout: timeout, wait_until: wait_until)
  end

  # @rbs return: untyped -- Result
  def name
    @name || ''
  end

  # @rbs return: untyped -- Result
  def url
    @url
  end

  # @rbs return: untyped -- Result
  def parent_frame
    @parent_frame
  end

  protected def _child_frames
    @child_frames
  end

  # @rbs return: untyped -- Result
  def child_frames
    @child_frames.to_a
  end

  # @rbs return: untyped -- Result
  def detached?
    @detached
  end

  # @rbs url: untyped -- url parameter
  # @rbs path: untyped -- path parameter
  # @rbs content: untyped -- content parameter
  # @rbs type: untyped -- type parameter
  # @rbs id: untyped -- id parameter
  # @rbs return: untyped -- Result
  def add_script_tag(url: nil, path: nil, content: nil, type: nil, id: nil)
    @main_world.add_script_tag(url: url, path: path, content: content, type: type, id: id)
  end

  # @rbs url: untyped -- url parameter
  # @rbs path: untyped -- path parameter
  # @rbs content: untyped -- content parameter
  # @rbs return: untyped -- Result
  def add_style_tag(url: nil, path: nil, content: nil)
    @main_world.add_style_tag(url: url, path: path, content: content)
  end

  # @rbs selector: untyped -- selector parameter
  # @rbs delay: untyped -- delay parameter
  # @rbs button: untyped -- button parameter
  # @rbs click_count: untyped -- click_count parameter
  # @rbs return: untyped -- Result
  def click(selector, delay: nil, button: nil, click_count: nil)
    @puppeteer_world.click(selector, delay: delay, button: button, click_count: click_count)
  end

  define_async_method :async_click

  # @rbs selector: untyped -- selector parameter
  # @rbs return: untyped -- Result
  def focus(selector)
    @puppeteer_world.focus(selector)
  end

  define_async_method :async_focus

  # @rbs selector: untyped -- selector parameter
  # @rbs return: untyped -- Result
  def hover(selector)
    @puppeteer_world.hover(selector)
  end

  # @rbs selector: untyped -- selector parameter
  # @rbs values: Array[untyped] -- values parameter
  # @rbs return: untyped -- Result
  def select(selector, *values)
    @puppeteer_world.select(selector, *values)
  end

  define_async_method :async_select

  # @rbs selector: untyped -- selector parameter
  # @rbs return: untyped -- Result
  def tap(selector)
    @puppeteer_world.tap(selector)
  end

  define_async_method :async_tap

  # @rbs selector: untyped -- selector parameter
  # @rbs text: untyped -- text parameter
  # @rbs delay: untyped -- delay parameter
  # @rbs return: untyped -- Result
  def type_text(selector, text, delay: nil)
    @main_world.type_text(selector, text, delay: delay)
  end

  define_async_method :async_type_text

  # @rbs selector: untyped -- selector parameter
  # @rbs visible: untyped -- visible parameter
  # @rbs hidden: untyped -- hidden parameter
  # @rbs timeout: untyped -- timeout parameter
  # @rbs return: untyped -- Result
  def wait_for_selector(selector, visible: nil, hidden: nil, timeout: nil)
    query_handler_manager = Puppeteer::QueryHandlerManager.instance
    query_handler_manager.detect_query_handler(selector).wait_for(self, visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_selector

  # @rbs milliseconds: untyped -- milliseconds parameter
  # @rbs return: untyped -- Result
  def wait_for_timeout(milliseconds)
    Puppeteer::AsyncUtils.sleep_seconds(milliseconds / 1000.0)
  end

  # @rbs xpath: untyped -- xpath parameter
  # @rbs visible: untyped -- visible parameter
  # @rbs hidden: untyped -- hidden parameter
  # @rbs timeout: untyped -- timeout parameter
  # @rbs return: untyped -- Result
  def wait_for_xpath(xpath, visible: nil, hidden: nil, timeout: nil)
    param_xpath =
      if xpath.start_with?('//')
        ".#{xpath}"
      else
        xpath
      end

    wait_for_selector("xpath/#{param_xpath}", visible: visible, hidden: hidden, timeout: timeout)
  end

  define_async_method :async_wait_for_xpath

  # @rbs page_function: untyped -- page_function parameter
  # @rbs args: untyped -- args parameter
  # @rbs polling: untyped -- polling parameter
  # @rbs timeout: untyped -- timeout parameter
  # @rbs return: untyped -- Result
  def wait_for_function(page_function, args: [], polling: nil, timeout: nil)
    @main_world.wait_for_function(page_function, args: args, polling: polling, timeout: timeout)
  end

  define_async_method :async_wait_for_function

  # @rbs return: untyped -- Result
  def title
    @puppeteer_world.title
  end

  # @rbs frame_payload: untyped -- frame_payload parameter
  # @rbs return: untyped -- Result
  def navigated(frame_payload)
    @name = frame_payload['name']
    @url = "#{frame_payload['url']}#{frame_payload['urlFragment']}"
  end

  # @rbs url: untyped -- url parameter
  # @rbs return: untyped -- Result
  def navigated_within_document(url)
    @url = url
  end

  # @rbs loader_id: untyped -- loader_id parameter
  # @rbs name: untyped -- name parameter
  # @rbs return: untyped -- Result
  def handle_lifecycle_event(loader_id, name)
    if name == 'init'
      @loader_id = loader_id
      @lifecycle_events.clear
    end
    @lifecycle_events << name
  end

  # @rbs return: untyped -- Result
  def handle_loading_started
    @has_started_loading = true
  end

  # @rbs return: untyped -- Result
  def handle_loading_stopped
    @lifecycle_events << 'DOMContentLoaded'
    @lifecycle_events << 'load'
  end

  # @rbs return: untyped -- Result
  def detach
    @detached = true
    @main_world.detach
    @puppeteer_world.detach
    if @parent_frame
      @parent_frame._child_frames.delete(self)
    end
    @parent_frame = nil
  end
end
