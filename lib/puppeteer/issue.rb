# rbs_inline: enabled

class Puppeteer::Issue
  # @rbs issue: Hash[String, untyped] -- CDP issue payload
  # @rbs return: void -- No return value
  def initialize(issue)
    @code = issue['code']
    @details = issue['details']
  end

  # @rbs return: String -- Issue code
  attr_reader :code

  # @rbs return: Hash[String, untyped] -- Issue details payload
  attr_reader :details
end
