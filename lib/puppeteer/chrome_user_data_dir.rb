# frozen_string_literal: true
# rbs_inline: enabled

require_relative './env'

module Puppeteer::ChromeUserDataDir
  CHANNELS = %w[chrome chrome-beta chrome-canary chrome-dev].freeze #: Array[String]

  MAC_DIR_NAMES = {
    'chrome' => 'Chrome',
    'chrome-beta' => 'Chrome Beta',
    'chrome-canary' => 'Chrome Canary',
    'chrome-dev' => 'Chrome Dev',
  }.freeze #: Hash[String, String]

  LINUX_DIR_NAMES = {
    'chrome' => 'google-chrome',
    'chrome-beta' => 'google-chrome-beta',
    'chrome-canary' => 'google-chrome-canary',
    'chrome-dev' => 'google-chrome-unstable',
  }.freeze #: Hash[String, String]

  WINDOWS_DIR_NAMES = {
    'chrome' => ['Google', 'Chrome', 'User Data'],
    'chrome-beta' => ['Google', 'Chrome Beta', 'User Data'],
    'chrome-canary' => ['Google', 'Chrome SxS', 'User Data'],
    'chrome-dev' => ['Google', 'Chrome Dev', 'User Data'],
  }.freeze #: Hash[String, Array[String]]

  # @rbs channel: (String | Symbol) -- Chrome release channel
  # @rbs platform: Symbol? -- Optional platform override
  # @rbs env: Hash[String, String] -- Environment variables
  # @rbs home: String? -- Home directory override
  # @rbs return: String -- Default user data directory
  def self.resolve_default(channel, platform: nil, env: ENV, home: nil)
    channel = normalize_channel(channel)
    platform ||= current_platform
    home ||= Dir.home

    case platform.to_sym
    when :windows
      base = env['LOCALAPPDATA']
      base = join_path(:windows, home, 'AppData', 'Local') if base.nil? || base.empty?
      join_path(:windows, base, *WINDOWS_DIR_NAMES.fetch(channel))
    when :darwin
      join_path(:darwin, home, 'Library', 'Application Support', 'Google', MAC_DIR_NAMES.fetch(channel))
    when :linux
      base = env['CHROME_CONFIG_HOME']
      base = env['XDG_CONFIG_HOME'] if base.nil? || base.empty?
      base = join_path(:linux, home, '.config') if base.nil? || base.empty?
      join_path(:linux, base, LINUX_DIR_NAMES.fetch(channel))
    else
      raise ArgumentError.new("Unsupported platform: #{platform}")
    end
  end

  # @rbs channel: (String | Symbol) -- Chrome release channel
  # @rbs return: String -- Normalized channel
  def self.normalize_channel(channel)
    normalized_channel = channel.to_s
    return normalized_channel if CHANNELS.include?(normalized_channel)

    raise ArgumentError.new("Invalid channel: '#{channel}'. Allowed channel is #{CHANNELS}")
  end

  # @rbs return: Symbol -- Current platform
  def self.current_platform
    if Puppeteer.env.windows?
      :windows
    elsif Puppeteer.env.darwin?
      :darwin
    else
      :linux
    end
  end
  private_class_method :current_platform

  # @rbs platform: Symbol -- Target platform
  # @rbs parts: String -- Path segments
  # @rbs return: String -- Joined path
  def self.join_path(platform, *parts)
    if platform == :windows
      parts.map(&:to_s).reject(&:empty?).join('\\')
    else
      File.join(*parts)
    end
  end
  private_class_method :join_path
end
