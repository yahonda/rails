# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module MySQL
      class Migration
        module Compatibility # :nodoc: all
          def self.find(version)
            version = version.to_s
            name = "V#{version.tr('.', '_')}"
            if const_defined?(name)
              return const_get(name)
            else
              ActiveRecord::Migration::Compatibility.find(version)
            end
          end

          class V6_0
            include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V6_0
          end

          class V5_2 < V6_0
            include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_2
          end

          class V5_1 < V5_2
            include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_1
            def create_table(table_name, options = {})
              super(table_name, options: "ENGINE=InnoDB", **options)
            end
          end

          class V5_0 < V5_1
            include ActiveRecord::ConnectionAdapters::MigrationCompatibility::V5_0
            def create_table(table_name, options = {})
              if (options[:id] != :bigint)
                if [:integer, :bigint].include?(options[:id]) && !options.key?(:default)
                  options[:default] = nil
                end
              end
              super
            end
          end
        end
      end
    end
  end
end
