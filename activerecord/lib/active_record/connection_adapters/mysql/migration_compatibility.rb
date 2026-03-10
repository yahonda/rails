# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module MigrationCompatibility # :nodoc: all
        module V7_0
          def change_column(table_name, column_name, type, **options)
            options[:collation] ||= :no_collation
            super
          end
        end

        module V5_1
          def create_table(table_name, **options)
            options = { options: "ENGINE=InnoDB", **options }
            super(table_name, **options)
          end
        end

        module V5_0
          def create_table(table_name, **options)
            # MySQL with bigint primary key preserves auto_increment behavior
            # and does not need default: nil (unlike integer primary key).
            # Signal to the base V5_0 compatibility class to skip setting default: nil.
            options[:_skip_pk_nil_default] = true if options[:id] == :bigint
            super
          end
        end

        MODULES = [
          [ActiveRecord::Migration::Compatibility::V5_0, V5_0],
          [ActiveRecord::Migration::Compatibility::V5_1, V5_1],
          [ActiveRecord::Migration::Compatibility::V7_0, V7_0],
        ]

        def self.module_for(migration_class)
          @module_cache ||= {}
          @module_cache[migration_class] ||= begin
            mods = MODULES
              .select { |compat_class, _| migration_class <= compat_class }
              .map { |_, mod| mod }

            Module.new { mods.each { |m| include m } } if mods.any?
          end
        end
      end
    end
  end
end
