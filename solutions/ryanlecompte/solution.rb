# I had a lot of fun doing this one! The following code makes
# the tests at https://gist.github.com/6ea0a0ba5702824075ab pass.
#
# NOTE: I normally would DRY some of this code up, but it's just a
# fun challenge and would never be deployed to production. :)

module MethodInstrumenter
  def self.instrument_path(path)
    @path = path
    @counts = 0
    @original_plus = Fixnum.instance_method(:+)
    attempt_eager_instrumentation(path)
  end

  def self.instrumented_path
    @path
  end

  def self.path_counts
    @counts
  end

  def self.increment_path_counter
    @counts = @original_plus.bind(@counts).call(1)
  end

  def self.instrumenting?
    @instrumenting
  end

  def self.instrument
    @instrumenting = true
    yield
    @instrumenting = false
  end

  def self.redefine_instance_method(klass, method_name)
    instrument do
      original_method = klass.instance_method(method_name)
      klass.send(:define_method, method_name) do |*args, &blk|
        MethodInstrumenter.increment_path_counter
        original_method.bind(self).call(*args, &blk)
      end
    end
  end

  def self.redefine_class_method(klass, method_name)
    instrument do
      original_method = klass.method(method_name)
      klass.define_singleton_method(method_name) do |*args, &blk|
        MethodInstrumenter.increment_path_counter
        original_method.call(*args, &blk)
      end
    end
  end

  def self.attempt_eager_instrumentation(path)
    klass_path, method_name = path.split(/[.#]/)
    klass = klass_path.split('::').inject(Object) { |acc, o| acc.const_get(o) }
    if path.include?('#')
      redefine_instance_method(klass, method_name)
    elsif path.include?('.')
      redefine_class_method(klass, method_name)
    else
      raise ArgumentError, "Unknown path: #{path}"
    end
  rescue => ex
    # we don't know about the class or method yet
  end
end

class Module
  def method_added(m)
    super if defined?(super)
    return if MethodInstrumenter.instrumenting?
    if MethodInstrumenter.instrumented_path == "#{name}##{m}"
      MethodInstrumenter.redefine_instance_method(self, m)
      return
    end

    # handle extend self case
    if self.class == Module &&
      singleton_class.ancestors.include?(self) &&
      MethodInstrumenter.instrumented_path == "#{name}.#{m}"
      MethodInstrumenter.redefine_class_method(self, m)
    end
  end

  def singleton_method_added(m)
    super if defined?(super)
    return if MethodInstrumenter.instrumenting?
    if MethodInstrumenter.instrumented_path == "#{name}.#{m}"
      MethodInstrumenter.redefine_class_method(self, m)
    end
  end

  def included(base)
    super if defined?(super)
    return if MethodInstrumenter.instrumenting?
    instance_methods(false).each do |m|
      if MethodInstrumenter.instrumented_path == "#{base.name}##{m}"
        MethodInstrumenter.redefine_instance_method(base, m)
      end
    end
  end

  def extended(base)
    super if defined?(super)
    return if MethodInstrumenter.instrumenting?
    base_name = Module === base ? base.name : base.class.name
    instance_methods(false).each do |m|
      if MethodInstrumenter.instrumented_path == "#{base_name}.#{m}"
        MethodInstrumenter.redefine_class_method(base, m)
      end
    end
  end
end

class Class
  def inherited(base)
    super if defined?(super)
    return if MethodInstrumenter.instrumenting?
    instance_methods(false).each do |m|
      if MethodInstrumenter.instrumented_path == "#{base.name}##{m}"
        MethodInstrumenter.redefine_instance_method(base, m)
      end
    end

    singleton_methods(false).each do |m|
      if MethodInstrumenter.instrumented_path == "#{base.name}.#{m}"
        MethodInstrumenter.redefine_class_method(base, m)
      end
    end
  end
end

MethodInstrumenter.instrument_path(ENV['COUNT_CALLS_TO'])
at_exit do
  if path = ENV['COUNT_CALLS_TO']
    puts '%s called %d times' % [path, MethodInstrumenter.path_counts]
  end
end

__END__

[ryan@:~] $ ruby meta_counter_test.rb 
Run options: 

# Running tests:

............................

Finished tests in 1.495487s, 18.7230 tests/s, 18.7230 assertions/s.

28 tests, 28 assertions, 0 failures, 0 errors, 0 skips