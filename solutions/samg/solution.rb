require 'set'

# A singleton responsible for installing instrumentation on the method
# specified in ENV['COUNT_CALLS_TO']
module Patcher
  COUNTS = Hash.new{|h,k| h[k] = 0}
  PATCHED = Set[]
  extend self

  # models a Ruby method signature such as Array#map or Base64.encode64
  #
  # It records the Class, method name, and scope (class or instance) referenced
  # by the string signature and provides convenience accessors to related
  # objects.
  class MethodSignature
    attr_accessor :klass, :scope, :method, :to_s, :klass_name
    def initialize(string)
      @to_s = string.to_s
      @klass_name, @scope, @method = string.to_s.split(/([#.])/)
    end

    def klass
      @klass ||= begin
        @klass_name.split('::').inject(Object){|n,i| n.const_get(i)}
      rescue NameError => e
      end
    end

    def method_object
      target && target.instance_method(method)
    rescue NameError => e
    end

    # the class the method is defined on
    def owner
      method_object && method_object.owner
    end

    # the class or the meta class depending on the scope
    def target
      @target ||= case scope
      when '#'
        klass
      when '.'
        klass && klass.class_eval{class << self; self; end}
      end
    end

    def instance_scope?
      scope == '#'
    end

    def class_scope?
      scope == '.'
    end
  end

  def signature
    @signature ||= MethodSignature.new(ENV['COUNT_CALLS_TO'])
  end

  # Check to see if the method should be patched with instrumentation and if so
  # call #patch_method.
  #
  # We look at the owner (where the method is defined) and signature so we can
  # install new instrumentation when the method is inherited, but later
  # overriden.
  def patch_method_safely(method_added=nil)
    return if PATCHED.include?([signature.owner, signature.to_s])
    return if Patcher.no_trace?
    # klass and method is defined.  So patch away
    if signature.klass && signature.target.instance_methods.include?(signature.method.intern)
      PATCHED.add([signature.owner, signature.to_s])
      patch_method
    end
  end

  # Actually instrument the method.  We handle all Ruby's weird symbol methods
  # here.
  def patch_method
    # handle ! and ? methods
    meth, punctuation = signature.method.to_s.sub(/([?!=])$/, ''), $1

    # handle +, -, [], etc.
    meth = case meth
    when '+'
      'plus'
    when '-'
      'minus'
    when '/'
      'slash'
    when '*'
      'splat'
    when '[]'
      'square'
    else
      meth
    end
    signature.target.class_eval <<-RB
      def #{meth}_with_counter#{punctuation}(*args, &block)
        #{meth}_without_counter#{punctuation}(*args, &block)
      ensure
        unless Patcher.no_trace?
          Patcher.no_trace do
            COUNTS['#{signature}'] += 1
          end
        end
      end
      Patcher.no_trace do
        alias #{meth}_without_counter#{punctuation} #{signature.method}
        alias #{signature.method} #{meth}_with_counter#{punctuation}
      end
    RB
  end

  # Disable tracing in the block so we don't count method calls in the
  # instrumentation itself, or get into stack overflow situations by
  # instrumenting our instrumented methods.
  #
  # Using a thread local variable should make this safe for threaded
  # applications.
  def self.no_trace(&block)
    Thread.current['no_trace'] = true
    block.call
  ensure
    Thread.current['no_trace'] = false
  end

  def self.no_trace?
    Thread.current['no_trace']
  end
end

# Patch the method if it's already available at this point.
Patcher.patch_method_safely

# Otherwise install hooks so we can instrument the method at the point it's
# defined.
class Class
  def inherited(base)
    #puts "Class#inherited called on #{base}"
    klass = Patcher.signature.klass
    if base == klass || base.ancestors.include?(klass)
      Patcher.signature.klass.class_eval do
        # patch right away if the method is inherited from a parent class
        Patcher.patch_method_safely

        if Patcher.signature.instance_scope?
          # or define a hook incase it's added later
          def self.method_added(method_name)
            if method_name.to_s == Patcher.signature.method
              Patcher.patch_method_safely(method_name)
            end
          end
        end

        if Patcher.signature.class_scope?
          def self.singleton_method_added(method_name)
            if method_name.to_s == Patcher.signature.method
              Patcher.patch_method_safely
            end
          end
        end
      end
    end
  end
end

class Module

  # handle methods like module A; def self.b; end; end
  def singleton_method_added(method_name)
    super if defined? super
    if method_name.to_s == Patcher.signature.method
      Patcher.patch_method_safely
    end
  end

  def extend_object_with_counting(base)
    #puts "Module#extend_object called #{base.inspect}"
    extend_object_without_counting(base)
    if base.respond_to? :ancestors
      klass = Patcher.signature.klass
      if base == klass || base.ancestors.include?(klass)
        # patch methods defined in the module already
        Patcher.patch_method_safely

        # add a callback in case the module defines more methods later
        def self.method_added(method_name)
          if method_name.to_s == Patcher.signature.method
            Patcher.patch_method_safely(method_name)
          end
        end
      end
    end
  end
  alias :extend_object_without_counting :extend_object
  alias :extend_object :extend_object_with_counting

  def append_features_with_counting(base)
    #puts "Module#append_features called #{base}"
    append_features_without_counting(base)
    klass = Patcher.signature.klass
    if base == klass || base.ancestors.include?(klass)
      Patcher.patch_method_safely
    end
  end
  alias :append_features_without_counting :append_features
  alias :append_features :append_features_with_counting

end

# Print our report at exit.
at_exit do
  puts "#{Patcher.signature} called #{Patcher::COUNTS[Patcher.signature.to_s]} times"
end
