# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior
        extend Base::Resolver

        class V7_0 < Base
          def change_column(table_name, column_name, type, **options)
            options[:collation] ||= :no_collation
            yield table_name, column_name, type, **options
          end
        end

        class V6_1 < V7_0
        end

        class V6_0 < V6_1
        end

        class V5_2 < V6_0
        end

        class V5_1 < V5_2
          def create_table(table_name, **options)
            options[:options] = "ENGINE=InnoDB" unless options.key?(:options)
            yield table_name, **options
          end
        end

        class V5_0 < V5_1
          # The framework V5_0 applies default: nil to integer/bigint ids and
          # runs before this behavior (the dispatch sits above V5_0 in the
          # chain), so MySQL's bigint-without-default is restored by dropping it
          # back out here rather than skipping it up front.
          def create_table(table_name, **options)
            options.delete(:default) if options[:id] == :bigint && options[:default].nil?
            super
          end
        end
      end
    end
  end
end
