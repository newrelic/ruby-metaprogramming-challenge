task :default => :all

solutions_dir = File.expand_path(File.join(File.dirname(__FILE__), 'solutions'))

test_and_benchmark = lambda do |solutions_to_test|
  tester = File.expand_path(File.join(File.dirname(__FILE__), 'test.rb'))
  bencher = File.expand_path(File.join(File.dirname(__FILE__), 'bench.rb'))

  Dir[File.join(solutions_dir, solutions_to_test)].each do |path|
    username = File.basename(path)
    Dir.chdir path
    `bundle` if File.exist?(File.join(path, 'Gemfile'))
    solution_file = File.join(path, 'solution.rb')
    puts
    puts "Testing #{username}"
    puts "===================================="
    system tester, solution_file
    puts "Benchmarking #{username}"
    puts "===================================="
    system bencher, solution_file
  end
end

desc "test and benchmark all"
task :all do
  test_and_benchmark['*']
end

Dir[File.join(solutions_dir, '*')].each do |path|
  username = File.basename(path)
  desc "test and benchmark #{username}"
  task username do
    test_and_benchmark[username]
  end
end
