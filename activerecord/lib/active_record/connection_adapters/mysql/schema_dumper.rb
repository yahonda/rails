module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module ColumnDumper
        def column_spec_for_primary_key(column)
          if column.bigint?
            spec = { id: :bigint.inspect }
            spec[:default] = schema_default(column) || 'nil' unless column.auto_increment?
            spec[:unsigned] = 'true' if column.unsigned?
          elsif default_primary_key?(column) && column.unsigned?
            spec = { unsigned: 'true' }
          else
            spec = super
          end
          spec
        end

        def prepare_column_options(column)
          spec = super
          spec[:unsigned] = 'true' if column.unsigned?
          spec
        end

        def migration_keys
          super + [:unsigned]
        end

        private

        def default_primary_key?(column)
          super && column.auto_increment?
        end

        def schema_type(column)
          case column.sql_type
          when /\Atimestamp\b/
            :timestamp
          when 'tinyblob'
            :blob
          else
            super
          end
        end

        def schema_limit(column)
          super unless column.type == :boolean
        end

        def schema_precision(column)
          super unless /time/ === column.sql_type && column.precision == 0
        end

        def schema_collation(column)
          if column.collation && table_name = column.instance_variable_get(:@table_name)
            @table_collation_cache ||= {}
            @table_collation_cache[table_name] ||= select_one("SHOW TABLE STATUS LIKE '#{table_name}'")["Collation"]
            column.collation.inspect if column.collation != @table_collation_cache[table_name]
          end
        end
      end
    end
  end
end
