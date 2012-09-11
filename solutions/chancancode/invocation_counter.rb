# Since I'm not a big fan of polluting "global" level objects (Class, Module,
# Kernel, etc), I tried to come up with a method that limit the "damage" to
# objects where this feature is explicitly "turned on". One of the more
# "obvious" solutions that satisfies this requirement would be...
# 
# class MyClass
#   include InvocationCounter
#   count_invocaions_to :my_method
# 
#   def my_method
#     ...
#   end
# end
# 
# The downside of this is that the programmer will need to first include some
# module, and then separately declare what methods to count. (An alternative
# would be to include this in Object or Kernel, but as I said, I'm not a fan.)
# Also, it would likely require polluting the target object with the counter's
# internal states (such as the invocation count).
# 
# Since this is a meta-programming challenge, it's only fitting that I subclass
# Module :) Besides trying to be cool, the motivation for doing so is to
# provide a nicer API so that the programmer can turn on the feature AND
# declare what to count in one go:
# 
# class MyClass
#   include InvocationCounter.new(:my_method)
# 
#   def my_method
#     ...
#   end
# end
# 
# Personally, I think this is quite nice as it's pretty clear and concise, and
# it also keeps the counter's internal state to itself instead of mixing them
# into the target object.

class InvocationCounter < Module
  def included(base)
    attach_self_reference(base)
    attach_counter(base)
  end

  def extended(base)
    attach_self_reference(base.singleton_class, true)
    attach_counter(base.singleton_class, true)
  end

  attr_reader :target_method
  attr_reader :count

  def initialize(target_method)
    @target_method = target_method
    @count = 0
    @attached = false
  end

  def attached?
    @attached
  end

  def invoked
    if @count.respond_to? :'+_without_counter'
      @count = @count.send(:'+_without_counter', 1)
    else
      @count += 1
    end
  end

  private

  def attach_self_reference(base, singleton = false)
    unless base.respond_to? :invocation_counters
      base.instance_variable_set :@invocation_counters, {}
      base.singleton_class.class_eval { attr_reader :invocation_counters }
    end

    if singleton && ! base.method_defined?(:singleton_invocation_counters)
      base.class_eval do
        define_method :singleton_invocation_counters do
          base.invocation_counters
        end
      end
    end

    base.invocation_counters[target_method] = self
  end

  def attach_counter(base, singleton = false)
    if instance_method_defined?(base, target_method)
      defer = false
    else
      defer = true
      define_placeholder_method(base, target_method)
    end

    this = self

    with_counter     = "#{target_method}_with_counter".to_sym
    withouth_counter = "#{target_method}_without_counter".to_sym

    base.class_eval do
      define_method(with_counter) do |*args, &block|
        this.invoked
        send(withouth_counter, *args, &block)
      end
    end

    alias_method_chain base, target_method, 'counter'

    if defer
      # Unfortunately, metaclasses don't behave exactly like normal classes...
      target_class = singleton ? base : base.singleton_class
      target_hook  = singleton ? :singleton_method_added : :method_added
      with_hook    = "#{target_hook}_with_#{target_method}_hook".to_sym
      without_hook = "#{target_hook}_without_#{target_method}_hook".to_sym

      unless instance_method_defined?(target_class, target_hook)
        define_placeholder_method(target_class, target_hook)
      end

      target_class.class_eval do
        define_method(with_hook) do |method_name|
          if ! this.attached? && method_name == this.target_method
            this.instance_variable_set :@attached, true
            this.send :alias_method_chain, base, this.target_method, 'counter'
          end
          send(without_hook, method_name)
        end
      end

      alias_method_chain target_class, target_hook, "#{target_method}_hook"

      @attached = false
    else
      @attached = true
    end
  end

  def alias_method_chain(klass, method_name, feature)
    method_name_with    = "#{method_name}_with_#{feature}".to_sym
    method_name_without = "#{method_name}_without_#{feature}".to_sym
    klass.send(:alias_method, method_name_without, method_name.to_sym)
    klass.send(:alias_method, method_name.to_sym, method_name_with)
  end

  def instance_method_defined?(klass, method_name)
    klass.instance_methods(false).include? method_name.to_sym
  end

  def define_placeholder_method(klass, method_name)
    klass.class_eval do
      define_method(method_name) do |*args, &block|
        if defined?(super)
          super(*args,&block)
        else
          method_missing(method_name, *args, &block)
        end
      end
    end
  end
end
