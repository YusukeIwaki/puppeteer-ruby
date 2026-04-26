# rbs_inline: enabled

class Puppeteer::Extension
  # @rbs id: String -- Extension id
  # @rbs version: String -- Extension version
  # @rbs name: String -- Extension name
  # @rbs path: String -- Extension path
  # @rbs enabled: bool -- Whether extension is enabled
  # @rbs browser: Puppeteer::Browser -- Browser instance
  # @rbs return: void -- No return value
  def initialize(id:, version:, name:, path:, enabled:, browser:)
    @id = id
    @version = version
    @name = name
    @path = path
    @enabled = enabled
    @browser = browser
  end

  # @rbs return: String -- Extension id
  attr_reader :id

  # @rbs return: String -- Extension version
  attr_reader :version

  # @rbs return: String -- Extension name
  attr_reader :name

  # @rbs return: String -- Extension path
  attr_reader :path

  # @rbs return: bool -- Whether extension is enabled
  attr_reader :enabled

  # @rbs return: Array[Puppeteer::CdpWebWorker] -- Extension workers
  def workers
    extension_prefix = "chrome-extension://#{@id}"
    extension_targets = @browser.targets.select do |target|
      target.type == 'service_worker' && target.url.start_with?(extension_prefix)
    end
    extension_targets.filter_map do |target|
      target.worker
    rescue
      nil
    end
  end

  # @rbs return: Array[Puppeteer::Page] -- Extension pages
  def pages
    extension_prefix = "chrome-extension://#{@id}"
    extension_targets = @browser.targets.select do |target|
      target_url = target.url
      ['page', 'background_page'].include?(target.type) && target_url.start_with?(extension_prefix)
    end
    extension_targets.filter_map do |target|
      target.as_page
    rescue
      nil
    end
  end

  # @rbs page: Puppeteer::Page -- Target page
  # @rbs return: void -- No return value
  def trigger_action(page)
    page.browser.send(:connection).send_message('Extensions.triggerAction', {
      id: @id,
      targetId: page._tab_id,
    })
  end
end
