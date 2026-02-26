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
    git_files = `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/}) || f.include?(".git") || f.include?(".circleci") || f.start_with?("development/")
    end
    sig_files = Dir.glob("sig/**/*.rbs")
    git_files + sig_files
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2'
  spec.add_dependency "async", ">= 2.35.1", "< 3.0"
  spec.add_dependency "async-http", ">= 0.60", "< 1.0"
  spec.add_dependency "async-websocket", ">= 0.27", "< 1.0"
  spec.add_dependency 'base64'
  spec.add_dependency 'mime-types', '>= 3.0'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'chunky_png'
  spec.add_development_dependency 'dry-inflector'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake', '~> 13.3.1'
  spec.add_development_dependency 'rspec', '~> 3.13.2'
  spec.add_development_dependency 'rspec_junit_formatter' # for CircleCI.
  spec.add_development_dependency 'rbs-inline'
  spec.add_development_dependency 'rubocop', '~> 1.85.0'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.9.0'
  spec.add_development_dependency 'sinatra', '< 5.0.0'
  spec.add_development_dependency 'steep'
  spec.add_development_dependency 'webrick'
end
