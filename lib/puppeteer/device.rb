class Puppeteer::Device
  # @param name [String]
  # @param user_agent [String]
  # @param viewport [Viewport]
  def initialize(name:, user_agent:, viewport:)
    @name = name
    @user_agent = user_agent
    @viewport = viewport
  end

  attr_reader :name, :user_agent, :viewport
end
