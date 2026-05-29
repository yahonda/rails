# frozen_string_literal: true

module ActiveRecord
  class Migration
    class CompatibilityStrategy < ExecutionStrategy
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
