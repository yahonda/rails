# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior

        class V7_0 < Base
          def disable_extension(name, **options)
            options[:force] = :cascade
            yield name, options
          end

          def add_foreign_key(from_table, to_table, **options)
            options[:deferrable] = :immediate if options[:deferrable] == true
            yield from_table, to_table, options
          end
        end

        class V6_1 < V7_0
          def add_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            yield table_name, column_name, type, options
          end

          def change_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            yield table_name, column_name, type, options
          end

          def new_column_definition(name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            yield name, type, options
          end
        end

        class V6_0 < V6_1
        end

        class V5_2 < V6_0
        end

        class V5_1 < V5_2
          def change_column(table_name, column_name, type, **options)
            super(table_name, column_name, type, **options.except(:default, :null, :comment))
            connection.change_column_default(table_name, column_name, options[:default]) if options.key?(:default)
            connection.change_column_null(table_name, column_name, options[:null], options[:default]) if options.key?(:null)
            connection.change_column_comment(table_name, column_name, options[:comment]) if options.key?(:comment)
          end
        end

        class V5_0 < V5_1
          def create_table(table_name, **options)
            if options[:id] == :uuid && !options.key?(:default)
              options[:default] = "uuid_generate_v4()"
            end
            yield table_name, options
          end
        end

        STRATEGIES = [
          [ActiveRecord::Migration::Compatibility::V5_0, V5_0],
          [ActiveRecord::Migration::Compatibility::V5_1, V5_1],
          [ActiveRecord::Migration::Compatibility::V6_1, V6_1],
          [ActiveRecord::Migration::Compatibility::V7_0, V7_0],
        ].freeze

        def self.for(migration_class)
          version_class = ActiveRecord::Migration::Compatibility.version_for(migration_class)
          return Base if version_class.nil?
          pair = STRATEGIES.find { |version, _| version_class <= version }
          pair ? pair.last : Base
        end
      end
    end
  end
end
