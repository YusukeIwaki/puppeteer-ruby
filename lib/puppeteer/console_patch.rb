# frozen_string_literal: true

begin
  require 'console/event/failure'
  require 'console/terminal/formatter/failure'
rescue LoadError
  # Console is optional; skip patching if unavailable.
end

module Console
  module Event
    class Failure
      unless method_defined?(:extract_without_cycle_guard)
        alias extract_without_cycle_guard extract

        private def extract(exception, hash)
          seen = Thread.current[:console_failure_seen] ||= {}
          return if seen[exception.object_id]

          seen[exception.object_id] = true
          begin
            extract_without_cycle_guard(exception, hash)
          ensure
            seen.delete(exception.object_id)
            Thread.current[:console_failure_seen] = nil if seen.empty?
          end
        end
      end
    end
  end

  module Terminal
    module Formatter
      class Failure
        unless method_defined?(:format_without_nil_guard)
          alias format_without_nil_guard format

          def format(event, stream, prefix: nil, verbose: false, **options)
            event = event.dup
            event[:message] = event[:message].to_s
            format_without_nil_guard(event, stream, prefix: prefix, verbose: verbose, **options)
          end
        end
      end
    end
  end
end
