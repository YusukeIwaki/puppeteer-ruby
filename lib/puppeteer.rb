require 'concurrent'

module Puppeteer; end

require 'puppeteer/env'

# Custom data types.
require 'puppeteer/events'
require 'puppeteer/errors'
require 'puppeteer/geolocation'
require 'puppeteer/viewport'

# Modules
require 'puppeteer/concurrent_ruby_utils'
require 'puppeteer/define_async_method'
require 'puppeteer/debug_print'
require 'puppeteer/event_callbackable'
require 'puppeteer/if_present'

# Classes & values.
require 'puppeteer/aria_query_handler'
require 'puppeteer/browser'
require 'puppeteer/browser_context'
require 'puppeteer/browser_runner'
require 'puppeteer/cdp_session'
require 'puppeteer/connection'
require 'puppeteer/console_message'
require 'puppeteer/coverage'
require 'puppeteer/css_coverage'
require 'puppeteer/custom_query_handler'
require 'puppeteer/devices'
require 'puppeteer/dialog'
require 'puppeteer/dom_world'
require 'puppeteer/emulation_manager'
require 'puppeteer/exception_details'
require 'puppeteer/execution_context'
require 'puppeteer/file_chooser'
require 'puppeteer/frame'
require 'puppeteer/frame_manager'
require 'puppeteer/js_coverage'
require 'puppeteer/js_handle'
require 'puppeteer/keyboard'
require 'puppeteer/launcher'
require 'puppeteer/lifecycle_watcher'
require 'puppeteer/mouse'
require 'puppeteer/network_conditions'
require 'puppeteer/network_manager'
require 'puppeteer/page'
require 'puppeteer/protocol_stream_reader'
require 'puppeteer/puppeteer'
require 'puppeteer/query_handler_manager'
require 'puppeteer/remote_object'
require 'puppeteer/request'
require 'puppeteer/response'
require 'puppeteer/target'
require 'puppeteer/tracing'
require 'puppeteer/timeout_settings'
require 'puppeteer/touch_screen'
require 'puppeteer/version'
require 'puppeteer/wait_task'
require 'puppeteer/web_socket'
require 'puppeteer/web_socket_transport'

# subclasses
require 'puppeteer/element_handle'

# ref: https://github.com/puppeteer/puppeteer/blob/master/lib/Puppeteer.js
module Puppeteer
  module_function def method_missing(method, *args, **kwargs, &block)
    @puppeteer ||= ::Puppeteer::Puppeteer.new(
      project_root: __dir__,
      preferred_revision: '706915',
      is_puppeteer_core: true,
    )

    if kwargs.empty? # for Ruby < 2.7
      @puppeteer.public_send(method, *args, &block)
    else
      @puppeteer.public_send(method, *args, **kwargs, &block)
    end
  end
end
