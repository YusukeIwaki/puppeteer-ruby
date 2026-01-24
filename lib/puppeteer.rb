require "async"
require 'puppeteer/console_patch'

# Check for Ruby versions affected by https://bugs.ruby-lang.org/issues/20907
# which causes hangs due to "Attempt to unlock a mutex which is not locked" errors.
# Fixed in: Ruby 3.2.7+, 3.3.7+, 3.4+
ruby_version = Gem::Version.new(RUBY_VERSION)
if ruby_version >= Gem::Version.new('3.2.0') && ruby_version < Gem::Version.new('3.2.7')
  raise "Ruby #{RUBY_VERSION} has a known issue that causes puppeteer-ruby to hang. " \
        "Please upgrade to Ruby 3.2.7+ or 3.3.7+ or 3.4+. " \
        "See: https://github.com/socketry/async/issues/424"
elsif ruby_version >= Gem::Version.new('3.3.0') && ruby_version < Gem::Version.new('3.3.7')
  raise "Ruby #{RUBY_VERSION} has a known issue that causes puppeteer-ruby to hang. " \
        "Please upgrade to Ruby 3.3.7+ or 3.4+. " \
        "See: https://github.com/socketry/async/issues/424"
end

module Puppeteer; end

require 'puppeteer/env'

# Custom data types.
require 'puppeteer/events'
require 'puppeteer/errors'
require 'puppeteer/geolocation'
require 'puppeteer/viewport'

# Modules
require "puppeteer/async_utils"
require 'puppeteer/define_async_method'
require 'puppeteer/debug_print'
require 'puppeteer/event_callbackable'
require 'puppeteer/if_present'
require "puppeteer/reactor_runner"

# Classes & values.
require 'puppeteer/aria_query_handler'
require 'puppeteer/browser'
require 'puppeteer/browser_context'
require 'puppeteer/browser_runner'
require 'puppeteer/browser_connector'
require 'puppeteer/cdp_session'
require 'puppeteer/chrome_target_manager'
require 'puppeteer/connection'
require 'puppeteer/console_message'
require 'puppeteer/coverage'
require 'puppeteer/css_coverage'
require 'puppeteer/custom_query_handler'
require 'puppeteer/devices'
require 'puppeteer/dialog'
require 'puppeteer/emulation_manager'
require 'puppeteer/exception_details'
require 'puppeteer/executable_path_finder'
require 'puppeteer/execution_context'
require 'puppeteer/file_chooser'
require 'puppeteer/frame'
require 'puppeteer/frame_manager'
require 'puppeteer/http_request'
require 'puppeteer/http_response'
require 'puppeteer/isolated_world'
require 'puppeteer/js_coverage'
require 'puppeteer/js_handle'
require 'puppeteer/keyboard'
require 'puppeteer/launcher'
require 'puppeteer/lifecycle_watcher'
require 'puppeteer/mouse'
require 'puppeteer/network_conditions'
require 'puppeteer/network_event_manager'
require 'puppeteer/network_manager'
require 'puppeteer/page'
require 'puppeteer/protocol_stream_reader'
require 'puppeteer/puppeteer'
require 'puppeteer/p_selector_parser'
require 'puppeteer/p_query_handler'
require 'puppeteer/query_handler_manager'
require 'puppeteer/remote_object'
require 'puppeteer/target'
require 'puppeteer/task_manager'
require 'puppeteer/tracing'
require 'puppeteer/timeout_helper'
require 'puppeteer/timeout_settings'
require 'puppeteer/touch_handle'
require 'puppeteer/touch_screen'
require 'puppeteer/version'
require 'puppeteer/wait_task'
require 'puppeteer/web_worker'
require 'puppeteer/web_socket_transport'

# subclasses
require 'puppeteer/element_handle'
require 'puppeteer/locators'

# ref: https://github.com/puppeteer/puppeteer/blob/master/lib/Puppeteer.js
module Puppeteer
  @puppeteer ||= ::Puppeteer::Puppeteer.new(
    project_root: __dir__,
    preferred_revision: '706915',
    is_puppeteer_core: true,
  ).tap do |instance|
    instance.public_methods(false).each do |method_name|
      define_singleton_method(method_name) do |*args, **kwargs, &block|
        if kwargs.empty? # for Ruby < 2.7
          @puppeteer.public_send(method_name, *args, &block)
        else
          @puppeteer.public_send(method_name, *args, **kwargs, &block)
        end
      end
    end
  end
end
