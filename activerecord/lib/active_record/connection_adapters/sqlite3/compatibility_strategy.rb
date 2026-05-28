# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module SQLite3
      module CompatibilityStrategy # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::AdapterStrategy

        class V6_0 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_add_reference_options(_table_name, _ref_name, options)
            options[:type] = :integer
          end
        end
      end
    end
  end
end
