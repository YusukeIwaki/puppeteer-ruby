lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'puppeteer/version'

Gem::Specification.new do |spec|
  spec.name          = 'puppeteer-ruby'
  spec.version       = Puppeteer::VERSION
  spec.authors       = ['YusukeIwaki']
  spec.email         = ['q7w8e9w8q7w8e9@yahoo.co.jp']

  spec.summary       = 'A ruby port of puppeteer'
  spec.homepage      = 'https://github.com/YusukeIwaki/puppeteer-ruby'

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/}) || f.include?(".git") || f.include?(".circleci") || f.start_with?("development/")
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.6'
  spec.add_dependency 'concurrent-ruby', '~> 1.1.0'
  spec.add_dependency 'websocket-driver', '>= 0.6.0'
  spec.add_dependency 'mime-types', '>= 3.0'
  spec.add_development_dependency 'bundler', '~> 2.3.4'
  spec.add_development_dependency 'chunky_png'
  spec.add_development_dependency 'dry-inflector'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake', '~> 13.0.3'
  spec.add_development_dependency 'rollbar'
  spec.add_development_dependency 'rspec', '~> 3.11.0'
  spec.add_development_dependency 'rspec_junit_formatter' # for CircleCI.
  spec.add_development_dependency 'rubocop', '~> 1.31.0'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'sinatra'
  spec.add_development_dependency 'webrick'
  spec.add_development_dependency 'yard'
end
