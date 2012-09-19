### encoding: UTF-8

# I see your attempt to run ruby, and I raise you...
BEGIN {
  require "bundler/setup"

  require 'ripper'
  require 'ripper2ruby'

  # What good is Object without a snowman?
  class Object
    def ☃
      # Pass ourselves back to SnowTap for filtering as method names are not
      # always unique.
      SnowTap.inc(self)

      return self
    end
  end

  # SnowTap - A Ruby parsing class for tracing method calls.
  class SnowTap < Ripper::RubyBuilder
    class << self
      attr_accessor :call_count
      attr_accessor :class_name
      attr_accessor :method_name

      # A handy incrementer.  Use this method to increment the call count.
      # You'll have to pass in your class as there's no way to determine this
      # at compile time.
      def inc(object)
        # Cache this as eval() is expensive.  We do this here as we need to be
        # within the eval'd context to resolve the class name.
        @klass ||= eval(@class_name) rescue return

        if object.is_a?(Class) or object.is_a?(Module)
          return unless object == @klass
        else
          if object.class.included_modules.include?(@klass) or object.kind_of?(@klass)
            # Handle the edge case where object.class overrides the method
            # we're tracking on the superclass.
            if object.class != @klass and object.class == object.method(@method_name.to_sym).owner
              return
            end
          else
            return
          end
        end

        @call_count += 1
      end
    end

    # Src is simple a string of valid Ruby code.  Method signature is in the
    # form: Class#IntanceMethod.
    def initialize(src, method_signature)
      (class_name, @method_name) = method_signature.split(/[#.]/)
      self.class.call_count  = 0
      self.class.class_name  = class_name
      self.class.method_name = @method_name

      # Life is no fun until you supersize your source.
      super(src)
    end

    # As the parser parses ruby, it fires callbacks that correspond to language
    # token types.  Here, we'll catch call tokens.
    def on_call(target, separator, identifier)
      # If this method call matches our method signature, patch in a call to
      # the snowman just before the method.
      if identifier.to_s == @method_name
        dot     = Ruby::Token.new('.')
        snowman = Ruby::Identifier.new('☃')

        return Ruby::Call.new(Ruby::Call.new(target, dot, snowman), dot, identifier)
      end

      return super
    end

    def on_command_call(target, separator, identifier, args)
      # This fires for identifiers that are operators, e.g. a.<<(foo)
      if identifier.to_s == @method_name
        dot     = Ruby::Token.new('.')
        snowman = Ruby::Identifier.new('☃')

        return Ruby::Call.new(Ruby::Call.new(target, dot, snowman), dot, identifier, args)
      end

      return super
    end

    def on_binary(left, operator, right)
      # Fire for operators we're tracking
      operator = pop_token(:"@#{operator}", :pass => true, :right => right) 

      if operator.to_s == @method_name
        dot     = Ruby::Token.new('.')
        snowman = Ruby::Identifier.new('☃')

        return Ruby::Binary.new(operator, Ruby::Call.new(left, dot, snowman), right) if operator
      end

      return Ruby::Binary.new(operator, left, right) if operator
    end

    def on_aref(target, args)
      # Remember, [] is a method name too!
      if @method_name == '[]'
        args        ||= Ruby::ArgsList.new
        args.ldelim ||= pop_token(:@lbracket, :left => target)
        args.rdelim ||= pop_token(:@rbracket, :reverse => true, :pass => true, :left => args.ldelim)

        dot     = Ruby::Token.new('.')
        snowman = Ruby::Identifier.new('☃')

        return Ruby::Call.new(Ruby::Call.new(target, dot, snowman), nil, nil, args)
      end

      return super
    end
  end

  method_signature = ENV['COUNT_CALLS_TO']

  # Remember, we're never going to allow ruby to actually execute the code we
  # passed it.  Instead, we'll slurp it in for static code analysis first.
  src = File.read($0)

  # Parse the code, patching as we go.
  code = SnowTap.new(src, method_signature).parse

  # Now, it's time to run the patched code.
  eval(code.to_ruby)

  # All done!  Let's print our results.
  puts "#{method_signature} called #{SnowTap.call_count} times" 

  # This exit is important.  We've already run all the ruby we need to so let's
  # exit before the interpreter has a chance to execute it.
  exit
}
