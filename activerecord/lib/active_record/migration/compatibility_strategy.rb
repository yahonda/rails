# frozen_string_literal: true

module ActiveRecord
  class Migration
    class CompatibilityStrategy < ExecutionStrategy
      module Resolver
        def for(migration_class)
          version_class = Compatibility.version_for(migration_class)
          return CompatibilityStrategy unless version_class
          pair = version_pairs.find { |version, _| version_class <= version }
          pair ? pair.last : CompatibilityStrategy
        end

        private
          def version_pairs
            @version_pairs ||= constants.grep(/\AV\d+_\d+\z/)
              .map { |name| [Compatibility.const_get(name), const_get(name)] }
              .sort { |a, b| a.first <=> b.first }
          end
      end

      private
        def method_missing(method, *args, &block)
          if block
            yield(*args)
          else
            connection.send(method, *args)
          end
        end
        ruby2_keywords(:method_missing)

        def respond_to_missing?(method, include_private = false)
          connection.respond_to?(method, include_private) || super
        end

        def connection
          migration.connection
        end
    end
  end
end
