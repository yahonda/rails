# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      module CompatibilityStrategy # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::AdapterStrategy

        class V7_0 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_change_column_options(_table_name, _column_name, _type, options)
            options[:collation] ||= :no_collation
          end
        end

        class V5_1 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_create_table_options(_table_name, options)
            options[:options] = "ENGINE=InnoDB" unless options.key?(:options)
          end
        end

        class V5_0 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_create_table_options(_table_name, options)
            options[:_skip_id_default_nil] = true if options[:id] == :bigint
          end
        end
      end
    end
  end
end
