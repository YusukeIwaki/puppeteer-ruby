# frozen_string_literal: true

class ServerFixture < Smartest::Fixture
  suite_fixture :test_server do
    server = TestServer::Server.new
    server.start
    $shared_test_server = server
    cleanup do
      begin
        server.stop
      ensure
        $shared_test_server = nil
      end
    end
    server
  end

  suite_fixture :test_https_server do
    server = TestServer::Server.new(
      scheme: 'https',
      ssl_context: TestServer.ssl_context,
    )
    server.start
    $shared_https_test_server = server
    cleanup do
      begin
        server.stop
      ensure
        $shared_https_test_server = nil
      end
    end
    server
  end

  fixture :server do |test_server:|
    cleanup { test_server.clear_routes }
    test_server
  end

  fixture :https_server do |test_https_server:|
    cleanup { test_https_server.clear_routes }
    test_https_server
  end
end
