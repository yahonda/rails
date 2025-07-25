# frozen_string_literal: true

module ActiveRecord
  module AttributeMethods
    # = Active Record Attribute Methods \Query
    #
    # Adds query methods for attributes that return either +true+ or +false+
    # depending on the attribute type and value.
    #
    # For Boolean attributes this will return +true+ if the value is present
    # and return +false+ otherwise:
    #
    #   class Product < ActiveRecord::Base
    #   end
    #
    #   product = Product.new(archived: false)
    #   product.archived? # => false
    #   product.archived = true
    #   product.archived? # => true
    #
    # For Numeric attributes this will return +true+ if the value is a non-zero
    # number and return +false+ otherwise:
    #
    #   product.inventory_count = 0
    #   product.inventory_count? # => false
    #   product.inventory_count = 1
    #   product.inventory_count? # => true
    #
    # For other attributes it will return +true+ if the value is present
    # and return +false+ otherwise:
    #
    #   product.name = nil
    #   product.name? # => false
    #   product.name = " "
    #   product.name? # => false
    #   product.name = "Orange"
    #   product.name? # => true
    module Query
      extend ActiveSupport::Concern

      included do
        attribute_method_suffix "?", parameters: false
      end

      # Returns +true+ or +false+ for the attribute identified by +attr_name+,
      # depending on the attribute type and value.
      def query_attribute(attr_name)
        value = self.public_send(attr_name)

        query_cast_attribute(attr_name, value)
      end

      def _query_attribute(attr_name) # :nodoc:
        value = self._read_attribute(attr_name.to_s)

        query_cast_attribute(attr_name, value)
      end

      alias :attribute? :query_attribute
      private :attribute?

      private
        def query_cast_attribute(attr_name, value)
          case value
          when true        then true
          when false, nil  then false
          else
            if !type_for_attribute(attr_name) { false }
              if Numeric === value || !value.match?(/[^0-9]/)
                !value.to_i.zero?
              else
                return false if ActiveModel::Type::Boolean::FALSE_VALUES.include?(value)
                !value.blank?
              end
            elsif value.respond_to?(:zero?)
              !value.zero?
            else
              !value.blank?
            end
          end
        end
    end
  end
end
