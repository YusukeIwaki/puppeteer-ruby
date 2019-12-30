require_relative './launcher/base'
require_relative './launcher/browser_options'
require_relative './launcher/chrome'
require_relative './launcher/chrome_arg_options'
require_relative './launcher/launch_options'

# https://github.com/puppeteer/puppeteer/blob/master/lib/Launcher.js
module Puppeteer::Launcher

  # @param {string} projectRoot
  # @param {string} preferredRevision
  # @param {boolean} isPuppeteerCore
  # @param {string=} product
  # @return {!Puppeteer.ProductLauncher}
  module_function def new(project_root:, preferred_revision:, is_puppeteer_core:, product:)
    if product == 'firefox'
      raise NotImplementedError.new("FirefoxLauncher is not implemented yet.")
    end

    Chrome.new(
      project_root: project_root,
      preferred_revision: preferred_revision,
      is_puppeteer_core: is_puppeteer_core
    )
  end
end
