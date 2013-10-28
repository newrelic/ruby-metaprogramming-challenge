#!/usr/bin/env ruby 

BEGIN {

  require 'singleton'

  class Instrumentation
   
    include Singleton

    METHOD_PARSE_REGEX = /^(.+)([.#])([^.#]+)$/

    # Class level methods to make things cleaner outside of this code.
    %w( enable result count ).each do |m|
      define_singleton_method( m.to_sym ) do
        instance.send( m.to_sym )
      end
    end

    # This method must delegate to the instance as well, but takes args so couldn't use above.
    def self.handle_signature_change( *args )
      instance.handle_signature_change( *args )
    end

    # Instance methods...
    def initialize
      @count = 0
      @target_object = nil
      @target_type   = nil
      @target_method = nil
      @method_reference = nil
      @enabled = false
    end

    def enable
      configure
      @enabled = true
    end

    def get_curr_method_reference

      # First, attempt to find the requested type
      obj = ObjectSpace.const_get( @target_object )
      return nil if obj.nil?

      # Second, attempt to find the method ( of the right type ) and return if found.
      case @target_type
        when :instance
          return obj.instance_method( @target_method ) if obj.instance_methods.include?( @target_method )
        when :class
          return obj.method( @target_method ) if obj.methods.include?( @target_method )
      end

      # If we got nothing, return nil
      return nil

    end

    def while_disabled( &block )

      begin
        # Disable signature_change hooks until we are done with this iteration.
        @enabled = false

        yield

      ensure
        # We're done, re-enable signature_change hooks.
        @enabled = true
      end

    end

    def get_method_type_functions
      case @target_type
        when :instance
          old_method_type_function = 'instance_method'
          new_method_type_function = 'define_method'
        when :class
          old_method_type_function = 'method'
          new_method_type_function = 'define_singleton_method'
      end

      return { old: old_method_type_function, new: new_method_type_function }
    end

    def handle_signature_change( klass, method_name )
      return unless @enabled

      puts "Signature CHANGE: #{ klass } : #{ method_name }" if $DEBUG

      while_disabled do

        # Short circuit if we can't currently find the method.
        curr_reference = get_curr_method_reference

        if( ( not curr_reference.nil? ) and ( not @method_reference == curr_reference ) )

          # If we get here, either the method hasn't been wrapped OR has been replaced.

          method_types = get_method_type_functions

          # Instance method.
          code =<<-CODE

            class ::#{ @target_object }

              old_method = #{ method_types[:old] }( :#{ @target_method } )

              #{ method_types[:new] }( :#{ @target_method } ) do |*args|
                Instrumentation.count
                old_method.bind( self ).call( *args )
              end

            end

          CODE

          # puts code
          eval code

          @method_reference = get_curr_method_reference

        end

      end

    end

    def configure
      @target = ENV[ 'COUNT_CALLS_TO' ]

      if @target =~ METHOD_PARSE_REGEX
        @target_object = $1
        @target_type   = $2 == '#' ? :instance : :class
        @target_method = $3.to_sym # save time later, it really should always be a Symbol.
      else
        # No match, bail out!
        raise "ENV VAR COUNT_CALLS_TO improperly defined: #{ @target }"
      end
    end

    def count
      @count += 1
    end

    def result
      "#{ @target } called #{ @count } time#{ @count == 1 ? '' : 's' }"
    end

  end

  class Module

    def handle_signature_change( method_name )
      Instrumentation.handle_signature_change( self, method_name )
    end

    alias :method_added :handle_signature_change
    alias :method_removed :handle_signature_change
    alias :method_undefined :handle_signature_change

    alias :singleton_method_added :handle_signature_change
    alias :singleton_method_removed :handle_signature_change
    alias :singleton_method_undefined :handle_signature_change

  end

  class Class

    def handle_signature_change( method_name )
      Instrumentation.handle_signature_change( self, method_name )
    end

    alias :method_added :handle_signature_change
    alias :method_removed :handle_signature_change
    alias :method_undefined :handle_signature_change

    alias :singleton_method_added :handle_signature_change
    alias :singleton_method_removed :handle_signature_change
    alias :singleton_method_undefined :handle_signature_change

  end

  Instrumentation.enable
}

END {
  puts Instrumentation.result
}
