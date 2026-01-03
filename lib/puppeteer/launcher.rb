require_relative './launcher/browser_options'
require_relative './launcher/chrome'
require_relative './launcher/chrome_arg_options'
require_relative './launcher/launch_options'

# https://github.com/puppeteer/puppeteer/blob/main/src/node/Launcher.ts
module Puppeteer::Launcher
  # @param project_root [String]
  # @param prefereed_revision [String]
  # @param is_puppeteer_core [String]
  # @param product [String] 'chrome'
  # @return [Puppeteer::Launcher::Chrome]
  module_function def new(project_root:, preferred_revision:, is_puppeteer_core:, product:)
    unless is_puppeteer_core
      product ||= ENV['PUPPETEER_PRODUCT']
    end

    product = product.to_s if product
    if product && product != 'chrome'
      raise ArgumentError.new("Unsupported product: #{product}. Only 'chrome' is supported.")
    end

    Chrome.new(
      project_root: project_root,
      preferred_revision: preferred_revision,
      is_puppeteer_core: is_puppeteer_core,
    )
  end
end
