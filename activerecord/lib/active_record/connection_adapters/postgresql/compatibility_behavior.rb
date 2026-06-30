# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        class V7_0 < Base
          def disable_extension(name, **options)
            options[:force] = :cascade
            yield name, **options
          end

          def add_foreign_key(from_table, to_table, **options)
            options[:deferrable] = :immediate if options[:deferrable] == true
            yield from_table, to_table, **options
          end
        end

        # For Rails <= 6.1, :datetime was aliased to :timestamp on PostgreSQL,
        # so these methods map :datetime back to :timestamp for migrations
        # written for those versions. From Rails 7 onwards :datetime resolves
        # to whatever `PostgreSQLAdapter.datetime_type` is set to (the default
        # is still :timestamp).
        class V6_1 < V7_0
          def add_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            yield table_name, column_name, type, **options
          end

          def change_column(table_name, column_name, type, **options)
            type = :timestamp if type.to_sym == :datetime
            yield table_name, column_name, type, **options
          end

          module TableDefinition
            def new_column_definition(name, type, **options)
              type = :timestamp if type.to_sym == :datetime
              super
            end
          end
        end

        class V6_0 < V6_1
        end

        class V5_2 < V6_0
        end

        # Runs the real change_column first, then applies :default / :null /
        # :comment separately. `super` reaches V6_1#change_column, whose `yield`
        # invokes the operation the framework hands in as a block (the
        # forwarder). That "run the operation, then do more" need is why
        # Migration#method_missing passes the operation to the behavior as a
        # block rather than calling it directly.
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
            yield table_name, **options
          end
        end
      end
    end
  end
end
