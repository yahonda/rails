# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module SQLite3
      module CompatibilityBehavior # :nodoc: all
        Base = ActiveRecord::Migration::CompatibilityBehavior

        class V6_0 < Base
          def add_reference(table_name, ref_name, **options)
            options[:type] = :integer
            yield table_name, ref_name, options
          end
        end

        STRATEGIES = [
          [ActiveRecord::Migration::Compatibility::V6_0, V6_0],
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
