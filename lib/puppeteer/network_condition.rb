class Puppeteer::NetworkCondition
  # @param download [Number] Download speed (bytes/s)
  # @param upload [Number] Upload speed (bytes/s)
  # @param latency [Number] Latency (ms)
  def initialize(download:, upload:, latency:)
    @download = download
    @upload = upload
    @latency = latency
  end

  attr_reader :download, :upload, :latency
end
