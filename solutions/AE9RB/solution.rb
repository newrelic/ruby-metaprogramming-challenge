# by David Turnbull AE9RB
# Tested with Ruby 1.9.2p320
# Extremely minimal solution.

lambda do
  
  return unless count_calls_to = ENV['COUNT_CALLS_TO']
  return unless match = count_calls_to.match(/(.+)(#|\.)(.+)/)
  klass, kind, kall = match.captures
  kall = kall.to_sym
  count = 0
  enabled = false
  stopper = false # Stop stack recursion for Fixnum#+

  enabler = Proc.new do |owner|
    original_name = "__#{kall}_original_for_count_calls_to".to_sym
    counter_name = "__#{kall}_counter_for_count_calls_to".to_sym
    owner.class_eval do
      define_method(counter_name) do |*args, &blk|
        if !stopper
          stopper = true
          count += 1
          stopper = false
        end
        send original_name, *args, &blk
      end
      alias_method original_name, kall
      alias_method kall, counter_name
    end
  end

  inserter = Proc.new do |method|
    if method == kall
      if self.name == klass
        if !enabled
          enabled = true
          enabler.call((kind == '#') ? self : self.singleton_class)
        end
      else
        self.send(:define_singleton_method, :inherited, Proc.new do |owner|
          enabler.call((kind == '#') ? self : self.singleton_class)
        end)
      end
    end
  end
  
  includer = Proc.new do |owner|
    if owner_const = owner.const_get(klass, true) rescue nil
      if !enabled && owner_const.name == klass
        if owner == owner_const && kind == '#' || owner != owner_const && kind == '.'
          enabled = true
          enabler.call owner rescue enabled = false
        end
      end
    end
  end

  extender = Proc.new do |owner| 
    includer.call owner.singleton_class
    owner.send(:define_singleton_method, :method_added, inserter)
  end
  
  begin
    enabler.call eval(klass) if kind == '#'
    enabler.call eval(klass).singleton_class if kind == '.'
    enabled = true
  rescue
    ::Module.send(:define_method, :method_added, inserter) if kind == '#'
    ::Module.send(:define_method, :singleton_method_added, inserter) if kind == '.'
    ::Module.send(:define_method, :included, includer)
    ::Module.send(:define_method, :extended, extender)
  end
  
  at_exit do
    puts "#{count_calls_to} called #{count} times."
  end
  
end.call
