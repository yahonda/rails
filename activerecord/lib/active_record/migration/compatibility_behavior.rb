# frozen_string_literal: true

module ActiveRecord
  class Migration
    class CompatibilityBehavior # :nodoc:
      module Resolver # :nodoc:
        def for(migration_class) # :nodoc:
          version_class = Compatibility.version_for(migration_class)
          return CompatibilityBehavior unless version_class
          # version_pairs is oldest-first; a behavior covers its own version and older.
          # Pick the lowest defined version >= the migration's, else the no-op base.
          pair = version_pairs.find { |version, _| version_class <= version }
          pair ? pair.last : CompatibilityBehavior
        end

        private
          def version_pairs
            @version_pairs ||= constants.grep(/\AV\d+_\d+\z/)
              .map { |name| [Compatibility.const_get(name), const_get(name)] }
              .sort { |a, b| a.first <=> b.first }
          end
      end

      def initialize(migration)
        @migration = migration
      end

      private
        attr_reader :migration

        def method_missing(method, *args)
          yield(*args)
        end
        ruby2_keywords(:method_missing)

        def connection
          migration.connection
        end
    end
  end
end
