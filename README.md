[![Archived header](https://github.com/newrelic/open-source-office/raw/master/examples/categories/images/Archived.png)](https://github.com/newrelic/open-source-office/blob/master/examples/categories/index.md#archived)

Metaprogramming Challenge
=========================

This repo contains solutions to a metaprogramming challenge created at New
Relic, as well as a test and benchmark suite for the solutions.

You can test and benchmark all of the included solutions by running:

    rake

You can test and benchmark a specific solution by invoking rake with the
solution author's github name.  For example:

    rake samg


The challenge is:
----

**Your challenge, should you choose to accept it, is to write a Ruby library
that will modify an existing program to output the number of times a specific
method is called.**

You solution library should be required at the top of the host program, or via
ruby's -r flag (i.e. `ruby -r ./solution.rb host_program.rb`)

Your solution library should read the environment variable `COUNT_CALLS_TO` to
determine the method it should count.  Valid method signatures are `Array#map!`,
`ActiveRecord::Base#find`, `Base64.encode64`, etc.

Your solution library should count calls to that method, and print the method
signature and the number of times it was called when the program exits.

Also, your solution should have a minimal impact on the program's running time.
Sorry `set_trace_func`.

Here is an example of a one line program which is altered to count calls to
`String#size`

    COUNT_CALLS_TO='String#size' ruby -r ./solution.rb -e '(1..100).each{|i| i.to_s.size if i.odd? }'
    String#size called 50 times


Here's another more complex example:

    COUNT_CALLS_TO='B#foo' ruby -r ./solution.rb -e 'module A; def foo; end; end; class B; include A; end; 10.times{B.new.foo}'
    B#foo called 10 times


Your solution:
----

If you have a novel or interesting solution to this challenge feel free to fork and send a pull request.
