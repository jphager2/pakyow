require "pakyow/support/deep_dup"

module Pakyow
  module Support
    # Provides control over how state is defined on an object, and how state is
    # shared across object instances and subclasses.
    #
    # You define the type of state provided by an object, along with any global
    # state for that object type. When an instance is created or the definable
    # object is subclassed, the new object inherits the global state and can be
    # extended with its own state.
    #
    # Once an instance has been created, global state for that object is frozen.
    #
    # Defineable objects' `initialize` method should always call super with
    # the block to ensure that state is inherited correctly.
    #
    # @example
    #   class SomeDefineableObject
    #     include Support::Defineable
    #
    #     def initialize(some_arg, &block)
    #       # Do something with some_arg, etc.
    #
    #       super(&block)
    #     end
    #   end
    #
    # Defineable objects define class and instance `make` methods that
    # return an instance of the class.
    #
    # @example
    #   defineable = SomeDefineableObject.make(*args, &block)
    #   defineable.make(*args, &block)
    #
    module Defineable
      using DeepDup

      def self.included(base)
        base.extend ClassAPI
      end

      # @api private
      attr_reader :state

      def initialize(&block)
        # create mutable state for this instance based on global
        @state = self.class.state.each_with_object({}) { |(name, global_state), state|
          state[name] = State.new(name, global_state.object)
        }

        # set instance level state
        self.instance_eval(&block) if block_given?

        # merge global state
        @state.each do |name, state|
          state.instances.concat(self.class.state[name].instances)
        end

        # merge inherited state
        if inherited = self.class.inherited_state
          @state.each do |name, state|
            state.instances.concat(inherited[name].instances)
          end
        end

        # instance state is now immutable
        freeze
      end

      # Returns register instances for state.
      #
      def state_for(type)
        return [] unless @state.key?(type)
        @state[type].instances
      end

      # @api private
      def freeze
        @state.each { |_, state| state.freeze }
        @state.freeze
        super
      end

      # Provide default make method
      #
      def make(*args, &block)
        self.class.make(*args, &block)
      end

      module ClassAPI
        attr_reader :state, :inherited_state

        def inherited(subclass)
          super

          subclass.instance_variable_set(:@inherited_state, state.deep_dup)
          subclass.instance_variable_set(:@state, state.each_with_object({}) { |(name, state_instance), state|
            state[name] = State.new(name, state_instance.object)
          })
        end

        # Register a type of state that can be defined.
        #
        def stateful(name, object)
          name = name.to_sym
          (@state ||= {})[name] = State.new(name, object)
          method_body = Proc.new do |*args, &block|
            return @state[name] if block.nil?

            instance = object.make(*args, &block)

            @state[name] << instance
          end

          define_method name, &method_body
          define_singleton_method name, &method_body
        end

        # Define state for the object.
        #
        def define(&block)
          instance_eval(&block)
        end

        # Provide a default make method
        #
        def make(*args, &block)
          new(*args, &block)
        end
      end
    end

    # Contains state for a definable class or instance.
    #
    # @api private
    class State
      using DeepDup

      attr_reader :name, :object, :instances

      def initialize(name, object)
        @name = name.to_sym
        @object = object
        @instances = []
      end

      def initialize_copy(original)
        super
        @instances = original.instances.deep_dup
      end

      # TODO: we handle both instances and classes, so reconsider the variable naming
      def <<(instance)
        ancestors = if instance.respond_to?(:new)
          instance.ancestors
        else
          instance.class.ancestors
        end

        unless ancestors.include?(object)
          raise ArgumentError, "Expected instance of '#{object}'"
        end

        instances << instance
      end

      def freeze
        instances.each(&:freeze)
        instances.freeze
        super
      end
    end
  end
end
