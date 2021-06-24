class Puppeteer::ProtocolStreamReader
  def initialize(client:, handle:)
    @client = client
    @handle = handle
  end

  # @returns [Enumerable<String>]
  def read_as_chunks
    Enumerator.new do |out|
      io_read { |data| out << data }
      io_close
    end
  end

  private def io_read(&block)
    eof = false
    until eof
      response = @client.send_message('IO.read', handle: @handle)
      eof = response['eof']
      data =
        if response['base64Encoded']
          Base64.decode64(response['data'])
        else
          response['data']
        end
      block.call(data)
    end
  end


  private def io_close
    @client.send_message('IO.close', handle: @handle)
  end
end
