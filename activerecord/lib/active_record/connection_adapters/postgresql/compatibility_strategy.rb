# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module CompatibilityStrategy # :nodoc: all
        extend ActiveRecord::Migration::Compatibility::AdapterStrategy

        class V7_0 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_disable_extension_options(_name, options)
            options[:force] = :cascade
          end

          def apply_add_foreign_key_options(_from_table, _to_table, options)
            options[:deferrable] = :immediate if options[:deferrable] == true
          end
        end

        class V6_1 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def coerce_column_type(type, _options)
            type.to_sym == :datetime ? :timestamp : type
          end
        end

        class V5_1 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def split_change_column?
            true
          end
        end

        class V5_0 < ActiveRecord::Migration::Compatibility::BaseStrategy
          def apply_create_table_options(_table_name, options)
            if options[:id] == :uuid && !options.key?(:default)
              options[:default] = "uuid_generate_v4()"
            end
          end
        end
      end
    end
  end
end
