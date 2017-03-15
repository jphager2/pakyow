require "forwardable"

module Pakyow
  module Routing
    module Extension
      def self.included(base)
        if base.is_a?(Class)
          raise StandardError, "Expected `#{base}' to be a module"
        else
          base.instance_variable_set(:@__extension, Pakyow::Router(nil))
          base.extend(ClassMethods)
        end
      end

      module ClassMethods
        extend Forwardable

        def_delegators :@__extension, *[:func, :default, :group, :namespace, :template].concat(
          Router::SUPPORTED_METHODS.map { |method|
            method.downcase.to_sym
          }
        )

        def extended(base)
          if base.ancestors.include?(Router)
            puts "merging on #{base.inspect} #{self.inspect}"
            base.merge(@__extension)
          else
            raise StandardError, "Expected `#{base}' to be an instance of `Pakyow::Router'"
          end
        end
      end
    end
  end
end
