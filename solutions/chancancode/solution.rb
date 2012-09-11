require_relative 'invocation_counter'

->{
  # JavaScript-inspired use of anonymous proc to create a new scope to avoid
  # polluting the global space. Might cause some minor memory leaks.

  target   = ENV['COUNT_CALLS_TO']
  attached = false

  begin
    base, type, method = /(.+)([#\.])(.+)/.match(target).captures
    instance_method    = (type == '#')
  rescue NoMethodError
    abort "Invalid value for COUNT_CALLS_TO: #{target.inspect}"
  end

  constantize = ->{
    segments = base.split('::')
    context = Object

    begin
      until segments.empty?
        constant = segments.shift

        if context.const_defined?(constant, false)
          context = context.const_get(constant)
        else
          context = context.const_missing(constant)
        end
      end
    rescue NameError
      context = nil
    end

    context
  }

  try_attach_counter = ->(){
    unless attached
      context = constantize.()

      if context
        counter  = InvocationCounter.new(method.to_sym)
        attached = true

        if instance_method
          context.send :include, counter
        else
          context.extend counter
        end

        at_exit { puts "#{target} called #{counter.count} times" }

        # Clean up
        constantize = nil
        try_attach_counter = nil
      end
    end

    attached
  }

  unless try_attach_counter.()
    ->(){
      # Case 1 - base is a class
      # 
      # We can just attach the counter when the class gets defined and let it
      # worry about deferred attachment on the methods level.
      #
      Object.define_singleton_method(:inherited) do |by|
        try_attach_counter.() if ! attached && by.name.start_with?(base)
        super(by) if defined?(super)
      end

      # Case 2 - base is a module
      # 
      # Unfortunately, there are no good ways to tell when a new Module gets
      # defined, so we'll have to watch for the modules being included or
      # extended instead.
      # 
      body = ->(by){
        try_attach_counter.() if ! attached && self.name.start_with?(base)
        super(by) if defined?(super)
      }

      Module.class_eval do
        define_method(:included, body)
        define_method(:extended, body)
      end

      # However, that still doesn't cover the case when a module method is
      # defined without extending self, like so:
      # 
      # module M
      #   def self.module_method
      #   end
      # end
      # 
      # This requires some very dirty special treatment...
      # 
      Module.class_eval do
        define_method(:singleton_method_added) do |name|
          try_attach_counter.() if ! attached && 
                                   self.class == Module &&
                                   self.name.start_with?(base)
          super(name) if defined?(super)
        end
      end
    }.()
  end
}.()
