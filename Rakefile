require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

desc 'Run Smartest browser integration tests'
task :smartest do
  sh 'bundle', 'exec', 'smartest'
end

task default: %i[spec smartest]

desc 'Generate RBS files with rbs-inline'
task :rbs do
  sh 'bundle', 'exec', 'rbs-inline', '--output=sig', 'lib'
end

Rake::Task[:build].enhance([:rbs])
