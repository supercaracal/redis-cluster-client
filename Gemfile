# frozen_string_literal: true

source 'https://rubygems.org'
gemspec name: 'redis-cluster-client'

gem 'async-redis', platform: :mri
gem 'benchmark-ips'
gem 'hiredis-client', '~> 0.6'
gem 'logger'
gem 'memory_profiler'
gem 'minitest'
gem 'rake'
gem 'rubocop'
gem 'rubocop-minitest', require: false
gem 'rubocop-performance', require: false
gem 'rubocop-rake', require: false
gem 'stackprof', platform: :mri
gem 'vernier', platform: :mri if RUBY_ENGINE == 'ruby' && Integer(RUBY_VERSION.split('.').first) > 2
