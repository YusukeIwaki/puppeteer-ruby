require_relative './network_condition'

Puppeteer::NETWORK_CONDITIONS = {
  'Slow 3G' => Puppeteer::NetworkCondition.new(
    download: ((500 * 1000) / 8) * 0.8,
    upload: ((500 * 1000) / 8) * 0.8,
    latency: 400 * 5,
  ),
  'Fast 3G' => Puppeteer::NetworkCondition.new(
    download: ((1.6 * 1000 * 1000) / 8) * 0.9,
    upload: ((750 * 1000) / 8) * 0.9,
    latency: 150 * 3.75,
  ),
}

module Puppeteer::NetworkConditions
  module_function def slow_3g
    Puppeteer::NETWORK_CONDITIONS['Slow 3G']
  end

  module_function def fast_3g
    Puppeteer::NETWORK_CONDITIONS['Fast 3G']
  end
end
