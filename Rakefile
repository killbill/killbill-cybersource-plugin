#!/usr/bin/env rake

module TempFixForRakeLastComment
  def last_comment
    last_description
  end
end
Rake::Application.send :include, TempFixForRakeLastComment

# Install tasks to build and release the plugin
require 'bundler/setup'
Bundler::GemHelper.install_tasks

# Install test tasks
require 'rspec/core/rake_task'
namespace :test do
  desc 'Run RSpec tests'
  RSpec::Core::RakeTask.new do |task|
    task.name = 'spec'
    task.pattern = './spec/*/*_spec.rb'
  end

  namespace :remote do
    desc 'Run RSpec remote tests'
    RSpec::Core::RakeTask.new do |task|
      task.name = 'spec'
      task.pattern = './spec/*/remote/*_spec.rb'
    end
  end

  namespace :ci do
    desc 'Run RSpec CI tests'
    RSpec::Core::RakeTask.new do |task|
      task.name = 'spec'
      task.pattern = './spec/**/*_spec.rb'
      task.rspec_opts = '--tag ~ci_skip'
    end
  end
end

# Install tasks to package the plugin for Killbill
require 'killbill/rake_task'
Killbill::PluginHelper.install_tasks

# Run tests by default
task :default => 'test:spec'
