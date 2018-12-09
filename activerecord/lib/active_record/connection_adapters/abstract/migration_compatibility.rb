# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MigrationCompatibility
      module V4_2
      end

      module V5_0
        include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V4_2
        module TableDefinition
          def primary_key(name, type = :primary_key, **options)
            type = :integer if type == :primary_key
            super
          end

          def references(*args, **options)
            super(*args, type: :integer, **options)
          end
          alias :belongs_to :references
        end

        def create_table(table_name, options = {})
          # TODO: Need to remove adapter_name condition here
          if (adapter_name != "Mysql2") || (options[:id] != :bigint)
            if [:integer, :bigint].include?(options[:id]) && !options.key?(:default)
              options[:default] = nil
            end
          end

          # Since 5.1 PostgreSQL adapter uses bigserial type for primary
          # keys by default and MySQL uses bigint. This compat layer makes old migrations utilize
          # serial/int type instead -- the way it used to work before 5.1.
          unless options.key?(:id)
            options[:id] = :integer
          end

          if block_given?
            super do |t|
              yield compatible_table_definition(t)
            end
          else
            super
          end
        end

        def change_table(table_name, options = {})
          if block_given?
            super do |t|
              yield compatible_table_definition(t)
            end
          else
            super
          end
        end

        def create_join_table(table_1, table_2, column_options: {}, **options)
          column_options.reverse_merge!(type: :integer)

          if block_given?
            super do |t|
              yield compatible_table_definition(t)
            end
          else
            super
          end
        end

        def add_column(table_name, column_name, type, options = {})
          if type == :primary_key
            type = :integer
            options[:primary_key] = true
          end
          super
        end

        def add_reference(table_name, ref_name, **options)
          super(table_name, ref_name, type: :integer, **options)
        end
        alias :add_belongs_to :add_reference
      end

      module V5_1
        include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_0
      end

      module V5_2
        include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_1
      end

      module V6_0
        include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_2
      end
    end
  end
end
