#!/usr/bin/env ruby

BEGIN {

  require 'singleton'

  class Instrumentation

    include Singleton

    class Counter

      attr_reader :value

      def initialize
        @value = 0
      end

      def count
        @value += 1
      end

    end

    class Finder

      attr_reader :target_object, :target_type, :target_method, :target

      def initialize( target_object = nil, target_method = nil, target_type = nil )
        @target_object = target_object
        @target_method = target_method
        @target_type   = target_type
        @target        = nil

        @method_name_regex = /^(.+)([.#])([^.#]+)$/
      end

      def from_env( env_var_name )
        @target = ENV[ env_var_name ]
        raise "ENV variable '#{ env_var_name }' not set." if @target.nil?

        match_obj = @method_name_regex.match( @target )

        if( not match_obj.nil? )
          @target_object = match_obj[1]
          @target_type   = ( match_obj[2] == '.' ) ? :class : :instance
          @target_method = match_obj[3].to_sym
        else
          raise "Unable to parse ENV var value '#{ @target }'."
        end

      end

      def find_object

        return nil if @target_object.nil?

        begin
          return Object.const_get( @target_object )
        rescue NameError
          return nil
        end

      end

      def find_method

        # Ensure the requested class/module exists.
        found_obj = find_object
        return nil if found_obj.nil?

        found_obj = found_obj.singleton_class if @target_type == :class

        return nil unless found_obj.instance_methods.include?( @target_method )

        found_obj.instance_method( @target_method )

      end

    end

    class Replacer

      def initialize( finder_obj )
        @finder = finder_obj
        @method_reference = nil
      end

      def gen_temp_func_name
        char_string = ''
        4.times { char_string << rand( '0'.ord .. '9'.ord ).chr }

        "instrumented_temp_func_#{ char_string }".to_sym
      end

      def add_count_wrapper

        curr_reference = @finder.find_method
        return if ( curr_reference.nil? ) or ( curr_reference == @method_reference )

        target_object = @finder.find_object
        target_object = target_object.singleton_class if @finder.target_type == :class

        temp_name     = gen_temp_func_name
        target_method = @finder.target_method

        target_object.class_eval do
          alias_method temp_name, target_method

          define_method( target_method ) do |*args, &block|
            Instrumentation.count
            send( temp_name, *args, &block )
          end
        end

        # Now, pull a reference to the new version and store it for later.
        @method_reference = @finder.find_method

      end

    end

    class EventHandler

      def initialize( replacer_object )
        @enabled  = false
        @replacer = replacer_object
      end

      def set_enabled( new_state )
        @enabled = new_state
      end

      def enabled
        @enabled
      end

      def while_disabled( &block )
        set_enabled( false )

        yield

        set_enabled( true )
      end

      def handle_signature_change
        return if not @enabled

        while_disabled { @replacer.add_count_wrapper }
      end

    end

    def self.handle_signature_change
      instance.handle_signature_change if instance.enabled
    end

    def self.enable
      set_enabled( true )
      handle_signature_change
    end

    def self.disable
      set_enabled( false )
    end

    def self.enabled
      instance.enabled
    end

    def self.while_disable
      set_enabled( false )
    end

    def self.set_enabled( new_state = true )
      instance.set_enabled( new_state )
    end

    def self.result
      instance.result
    end

    def self.count
      instance.count
    end

    def initialize
      @counter       = Counter.new
      @finder        = Finder.new
      @replacer      = Replacer.new( @finder )
      @event_handler = EventHandler.new( @replacer )

      @finder.from_env( 'COUNT_CALLS_TO' )
    end

    def set_enabled( new_state = true )
      @event_handler.set_enabled( new_state == true )
    end

    def enabled
      @event_handler.enabled
    end

    def handle_signature_change
      @event_handler.handle_signature_change if enabled
    end

    def count
      @counter.count
    end

    def result
      "#{ @finder.target } called #{ @counter.value } time#{ @counter.value == 1 ? '' : 's' }."
    end

  end

  [ Class, Module ].each do |k|

    k.class_eval do

      define_method( :handle_signature_change ) do |arg|
        Instrumentation.handle_signature_change if Instrumentation.enabled
      end

      alias_method :method_added, :handle_signature_change
      alias_method :method_removed, :handle_signature_change
      alias_method :method_undefined, :handle_signature_change

      alias_method :singleton_method_added, :handle_signature_change
      alias_method :singleton_method_removed, :handle_signature_change
      alias_method :singleton_method_undefined, :handle_signature_change

      alias_method :included, :handle_signature_change
      alias_method :extended, :handle_signature_change
      alias_method :prepended, :handle_signature_change

      alias_method :inherited, :handle_signature_change if k == Class

    end

  end

  Instrumentation.enable
}

END {

  Instrumentation.disable

  puts Instrumentation.result
}

