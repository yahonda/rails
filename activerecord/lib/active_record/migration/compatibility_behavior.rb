# frozen_string_literal: true

module ActiveRecord
  class Migration
    class CompatibilityBehavior
      def initialize(migration)
        @migration = migration
      end

      private
        attr_reader :migration

        def method_missing(method, *args, **options)
          yield(*args, **options)
        end

        def connection
          migration.connection
        end
    end
  end
end
