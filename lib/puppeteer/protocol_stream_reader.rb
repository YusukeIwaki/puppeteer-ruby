class Puppeteer::ProtocolStreamReader
  def initialize(client:, handle:, path:)
    @client = client
    @handle = handle
    @path = path
  end

  def read
    StringIO.open do |out|
      if @path
        File.open(@path, 'wb') do |file|
          io_read do |data|
            out.write(data)
            file.write(data)
          end
        end
      else
        io_read { |data| out.write(data) }
      end
      io_close

      out.string
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
