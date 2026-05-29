# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module CompatibilityStrategy # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityStrategy

        class V7_0 < Base
          def change_column(table_name, column_name, type, **options)
            options[:collation] ||= :no_collation
            yield table_name, column_name, type, options
          end
        end

        class V5_1 < V7_0
          def create_table(table_name, **options)
            options[:options] = "ENGINE=InnoDB" unless options.key?(:options)
            yield table_name, options
          end
        end

        class V5_0 < V5_1
          # The framework V5_0 applies default: nil to integer/bigint ids and
          # runs before this strategy (the dispatch sits above V5_0 in the
          # chain), so MySQL's bigint-without-default is restored by dropping it
          # back out here rather than skipping it up front.
          def create_table(table_name, **options)
            options.delete(:default) if options[:id] == :bigint && options[:default].nil?
            super
          end
        end

        STRATEGIES = [
          [ActiveRecord::Migration::Compatibility::V5_0, V5_0],
          [ActiveRecord::Migration::Compatibility::V5_1, V5_1],
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
