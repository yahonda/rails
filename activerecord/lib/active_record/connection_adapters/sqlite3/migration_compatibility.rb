# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module SQLite3
      module MigrationCompatibility # :nodoc: all
        module V6_0
          def add_reference(table_name, ref_name, **options)
            options[:type] = :integer
            super
          end
        end

        MODULES = [
          [ActiveRecord::Migration::Compatibility::V6_0, V6_0],
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
