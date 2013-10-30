#!/usr/bin/env ruby

BEGIN {

  class Instrumentation

    class Counter

      def initialize
        @value = 0
      end

      def count
        @value = @value.succ
      end

      def value
        @value
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

      def enabled?
        @enabled == true
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

    ## MODULE METHODS ########################################################

    # NOTE: the only challenge here is that singleton uses Monitor, which uses 
    #       a bit of Fixnum math, messing up our counts for Fixnum#- & Fixnum#+
    require 'singleton'
    include Singleton

    def self.enable
      instance.enable
    end

    def self.disable
      instance.disable
    end

    def self.count
      instance.count
    end

    def self.handle_signature_change( arg = nil )
      instance.handle_signature_change
    end

    def self.result
      instance.result
    end


    ## INSTANCE METHODS ######################################################

    def initialize
      @counter       = Counter.new
      @finder        = Finder.new
      @replacer      = Replacer.new( @finder )
      @event_handler = EventHandler.new( @replacer )

      @finder.from_env( 'COUNT_CALLS_TO' )
    end

    def enable
      @event_handler.set_enabled( true )
    end

    def disable
      @event_handler.set_enabled( false )
    end

    def enabled?
      @event_handler.enabled?
    end

    def count
      @counter.count
    end

    def result
      target = @finder.target
      count  = @counter.value

      "#{ target } called #{ count } time#{ ( count == 1 ) ? '' : 's' }"
    end

    def handle_signature_change
      @event_handler.handle_signature_change
    end


  end

  [ Class, Module ].each do |k|

    k.class_eval do

      # Wrap all appropriate class/module modification notification methods.
      [ 
        [ :method_added ],
        [ :method_removed ],
        [ :method_undefined ],
        [ :singleton_method_added ],
        [ :singleton_method_removed ],
        [ :singleton_method_undefined ],
        [ :included ],
        [ :extended ],
        [ :prepended ],
        [ :inherited, Class ]
      ].each do |meth|
        next unless ( meth.size == 1 ) or ( meth[1] == k )

        old_method = method( meth[0] )

        define_method( meth[0] ) do |*args|
          Instrumentation.handle_signature_change
          old_method.call( *args )
        end
      end

    end

  end

  Instrumentation.enable
  Instrumentation.handle_signature_change
}

END {

  Instrumentation.disable

  puts Instrumentation.result
}

