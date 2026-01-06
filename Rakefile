require 'bundler/gem_tasks'

desc 'Generate RBS files with rbs-inline'
task :rbs do
  sh 'bundle', 'exec', 'rbs-inline', '--output=sig', 'lib'
end

Rake::Task[:build].enhance([:rbs])
