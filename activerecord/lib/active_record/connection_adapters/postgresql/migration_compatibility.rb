# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module MigrationCompatibility # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::AdapterModules

        module V7_0
          def disable_extension(name, **options)
            options[:force] = :cascade
            super
          end

          def add_foreign_key(from_table, to_table, **options)
            options[:deferrable] = :immediate if options[:deferrable] == true
            super
          end
        end

        # For Rails <= 6.1, :datetime was aliased to :timestamp on PostgreSQL;
        # from Rails 7 onwards it resolves to whatever
        # `PostgreSQLAdapter.datetime_type` is set to.
        module V6_1
          include V7_0

          def add_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            super
          end

          def change_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            super
          end

          module TableDefinition
            def new_column_definition(name, type, **options)
              type = :timestamp if type.to_sym == :datetime
              super
            end
          end
        end

        module V6_0
          include V6_1
        end

        module V5_2
          include V6_0
        end

        # Runs the real change_column first (`super` reaches V6_1, then the
        # strategy), then applies :default / :null / :comment separately.
        module V5_1
          include V5_2

          def change_column(table_name, column_name, type, **options)
            super(table_name, column_name, type, **options.except(:default, :null, :comment))
            connection = migration.connection
            connection.change_column_default(table_name, column_name, options[:default]) if options.key?(:default)
            connection.change_column_null(table_name, column_name, options[:null], options[:default]) if options.key?(:null)
            connection.change_column_comment(table_name, column_name, options[:comment]) if options.key?(:comment)
          end
        end

        module V5_0
          include V5_1

          def create_table(table_name, **options)
            if options[:id] == :uuid && !options.key?(:default)
              options[:default] = "uuid_generate_v4()"
            end
            super
          end
        end
      end
    end
  end
end
