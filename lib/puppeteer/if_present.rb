module Puppeteer::IfPresent
  # Similar to #try in ActiveSupport::CoreExt.
  #
  # Evaluate block with the target, only if target is not nil.
  # Returns nil if target is nil.
  #
  # --------
  # if_present(params['target']) do |target|
  #   Point.new(target['x'], target['y'])
  # end
  # --------
  def if_present(target, &block)
    raise ArgumentError.new('block must be provided for #if_present') if block.nil?
    return nil if target.nil?

    block.call(target)
  end
end
