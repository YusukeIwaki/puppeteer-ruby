# Original implementation, helpers.getExceptionMessage
class Puppeteer::ExceptionDetails
  # @param exception_details [Hash]
  def initialize(exception_details)
    @exception_details = exception_details
  end

  def message
    # "exceptionDetails"=>{"exceptionId"=>1, "text"=>"Uncaught", "lineNumber"=>12, "columnNumber"=>10, "url"=>"http://127.0.0.1:4567/error.html",
    #  "stackTrace"=>{"callFrames"=>[
    #   {"functionName"=>"c", "scriptId"=>"6", "url"=>"http://127.0.0.1:4567/error.html", "lineNumber"=>12, "columnNumber"=>10},
    #   {"functionName"=>"b", "scriptId"=>"6", "url"=>"http://127.0.0.1:4567/error.html", "lineNumber"=>8, "columnNumber"=>4},
    #   {"functionName"=>"a", "scriptId"=>"6", "url"=>"http://127.0.0.1:4567/error.html", "lineNumber"=>4, "columnNumber"=>4},
    #   {"functionName"=>"", "scriptId"=>"6", "url"=>"http://127.0.0.1:4567/error.html", "lineNumber"=>1, "columnNumber"=>0}
    #  ]},
    #  "exception"=>{"type"=>"object", "subtype"=>"error", "className"=>"Error", "description"=>"Error: Fancy error!\n    at c (http://127.0.0.1:4567/error.html:13:11)\n    at b (http://127.0.0.1:4567/error.html:9:5)\n    at a (http://127.0.0.1:4567/error.html:5:5)\n    at http://127.0.0.1:4567/error.html:2:1", "objectId"=>"{\"injectedScriptId\":3,\"id\":1}", "preview"=>{"type"=>"object", "subtype"=>"error", "description"=>"Error: Fancy error!\n    at c (http://127.0.0.1:4567/error.html:13:11)\n    at b (http://127.0.0.1:4567/error.html:9:5)\n    at a (http://127.0.0.1:4567/error.html:5:5)\n    at http://127.0.0.1:4567/error.html:2:1", "overflow"=>false, "properties"=>[{"name"=>"stack", "type"=>"string", "value"=>"Error: Fancy error!\n    at c (http://127.0.0.1:456…:5:5)\n    at http://127.0.0.1:4567/error.html:2:1"}, {"name"=>"message", "type"=>"string", "value"=>"Fancy error!"}]}}
    if @exception_details['exception']
      return exception_description_or_value(@exception_details['exception'])
    end

    messages = []
    messages << @exception_details['text']

    if @exception_details['stackTrace']
      @exception_details['stackTrace']['callFrames'].each do |call_frame|
        location = "#{call_frame['url']}:#{call_frame['lineNumber']}:#{call_frame['columnNumber']}"
        function_name = call_frame['functionName'] || '<anonymous>'
        messages << "at #{function_name} (#{location})"
      end
    end

    messages.join("\n    ")
  end

  private def exception_description_or_value(exception)
    exception['description'] || exception['value']
  end
end
