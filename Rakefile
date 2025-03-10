# encoding: utf-8

ENV["BRANCH"] = 'main'

require 'rubygems'
require 'rake'
require 'juwelier'
Juwelier::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://guides.rubygems.org/specification-reference/ for more options
  gem.name = "scout-essentials"
  gem.homepage = "http://github.com/mikisvaz/scout-essentials"
  gem.license = "MIT"
  gem.summary = %Q{Scout essential tools}
  gem.description = %Q{Things a scout can use anywhere}
  gem.email = "mikisvaz@gmail.com"
  gem.authors = ["Miguel Vazquez"]

  # dependencies defined in Gemfile
  
  gem.add_runtime_dependency 'term-ansicolor'
  gem.add_runtime_dependency 'yaml'
  gem.add_runtime_dependency 'rake'
end
Juwelier::RubygemsDotOrgTasks.new
require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

desc "Code coverage detail"
task :simplecov do
  ENV['COVERAGE'] = "true"
  Rake::Task['test'].execute
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "scout-essentials #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
