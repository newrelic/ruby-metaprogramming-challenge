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

      def initialize( target_object = nil, target_method = nil, target_type = nil )        @target_object = target_object
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
          @target_object = match_obj[1].capitalize
          @target_type = ( match_obj[2] == '.' ) ? :class : :instance
          @target_method = match_obj[3].to_sym
        else
          raise "Unable to parse ENV var value '#{ @target }'."
        end

      end

      def find_object
        return nil if @target_object.nil?

        result = nil

        begin
          result = ObjectSpace.const_get( @target_object )
        rescue NameError => err
          # Nothing to do here. @target doesn't exist yet.
        end

        result
      end

      def find_method
        found_obj = find_object
        if found_obj.nil? or @target_type.nil? or @target_method.nil?
          return nil
        end

        method_obj = nil

        begin

          case @target_type
            when :instance
              method_obj = found_obj.instance_method( @target_method )
            when :class
              method_obj = found_obj.method( @target_method )
          end

          puts "Found: #{ method_obj }"

        rescue NameError => err
          # Nothing to do here ... 
          puts "ERROR: #{ err }"
        end

        method_obj

      end

    end

    class Replacer

      def initialize( finder_obj )
        @finder = finder_obj
        @method_reference = nil
      end

      def gen_temp_func_name
        chars = %w( 0 1 2 3 4 5 6 7 8 9 )

        char_string = ''
        4.times { char_string << chars[ rand( chars.length ) ] }

        "instrumented_temp_func_#{ char_string }".to_sym
      end

      def prefix_class_method
        object = @finder.find_object
        target_method = @finder.target_method

        return if object.nil?

        temp_name = gen_temp_func_name

        object.instance_eval do

          alias_method temp_name, target_method

          define_method( target_method ) do |*args, &block|
            Instrumentation.count
            send( temp_name, *args, &block )
          end

        end

      end

      def prefix_instance_method
        object = @finder.find_object
        target_method = @finder.target_method

        return if object.nil?

        temp_name = gen_temp_func_name

        object.class_eval do

          alias_method temp_name, target_method

          define_method( target_method ) do |*args, &block|
            Instrumentation.count
            send( temp_name, *args, &block )
          end

        end

      end

      def add_count_wrapper
        curr_reference = @finder.find_method

        return if ( curr_reference.nil? ) or ( curr_reference == @method_reference )

        # Handle prefixing the method.
        if( @finder.target_type == :instance )
          prefix_instance_method
        else
          prefix_class_method
        end

        # Now, pull a reference to the new version.
        new_reference = @finder.find_method

        # And store it for later.
        @method_reference = new_reference

      end

    end

    class EventHandler

      def initialize( replacer_object )
        @enabled = false

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

  class Module

    def handle_signature_change( _ )
      Instrumentation.handle_signature_change if Instrumentation.enabled
    end

    # alias :old_method_added :method_added
    # alias :old_method_removed :method_removed
    # alias :old_method_undefined :method_undefined

    def method_added( method_name )
      handle_signature_change( method_name )
      # old_method_added( method_name )
    end

    def method_removed( method_name )
      handle_signature_change( method_name )
      # old_method_removed( method_name )
    end

    def method_undefined( method_name )
      handle_signature_change( method_name )
      # old_method_undefined( method_name )
    end

    # alias :old_singleton_method_added :singleton_method_added
    # alias :old_singleton_method_removed :singleton_method_removed
    # alias :old_singleton_method_undefined :singleton_method_undefined

    def singleton_method_added( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_added( method_name )
    end

    def singleton_method_removed( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_removed( method_name )
    end

    def singleton_method_undefined( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_undefined( method_name )
    end

  end

  class Class

    def handle_signature_change( _ )
      Instrumentation.handle_signature_change if Instrumentation.enabled
    end

    # alias :old_method_added :method_added
    # alias :old_method_removed :method_removed
    # alias :old_method_undefined :method_undefined

    def method_added( method_name )
      handle_signature_change( method_name )
      # old_method_added( method_name )
    end

    def method_removed( method_name )
      handle_signature_change( method_name )
      # old_method_removed( method_name )
    end

    def method_undefined( method_name )
      handle_signature_change( method_name )
      # old_method_undefined( method_name )
    end

    # alias :old_singleton_method_added :singleton_method_added
    # alias :old_singleton_method_removed :singleton_method_removed
    # alias :old_singleton_method_undefined :singleton_method_undefined

    def singleton_method_added( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_added( method_name )
    end

    def singleton_method_removed( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_removed( method_name )
    end

    def singleton_method_undefined( method_name )
      handle_signature_change( method_name )
      # old_singleton_method_undefined( method_name )
    end

  end

  Instrumentation.enable
}


# class Foo
#   def bar
#     :a
#   end

#   def self.bam
#     :b
#   end
# end

# class A
#   class B
#     class C
#       class D
#         class E
#           def b
#           end
#         end
#       end
#     end
#   end
# end

# module Super
#   def self.duper
#   end
# end

# 10.times do 
#   Foo.bam
#   Foo.new.bar
#   A::B::C::D::E.new.b
#   4 - 4
#   Super.duper
# end

#10.times { |n| n.to_s.sub! '1', '2' }


END {
  puts Instrumentation.result
}

