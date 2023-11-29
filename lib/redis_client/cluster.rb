# frozen_string_literal: true

require 'redis_client/cluster/concurrent_worker'
require 'redis_client/cluster/pipeline'
require 'redis_client/cluster/pub_sub'
require 'redis_client/cluster/router'
require 'redis_client/cluster/transaction' # TODO: remove

class RedisClient
  class Cluster
    ZERO_CURSOR_FOR_SCAN = '0'

    attr_reader :config

    def initialize(config, pool: nil, concurrency: nil, **kwargs)
      @config = config
      @concurrent_worker = ::RedisClient::Cluster::ConcurrentWorker.create(**(concurrency || {}))
      @router = ::RedisClient::Cluster::Router.new(config, @concurrent_worker, pool: pool, **kwargs)
      @command_builder = config.command_builder
    end

    def inspect
      "#<#{self.class.name} #{@router.node_keys.join(', ')}>"
    end

    def call(*args, **kwargs, &block)
      command = @command_builder.generate(args, kwargs)
      @router.send_command(:call_v, command, &block)
    end

    def call_v(command, &block)
      command = @command_builder.generate(command)
      @router.send_command(:call_v, command, &block)
    end

    def call_once(*args, **kwargs, &block)
      command = @command_builder.generate(args, kwargs)
      @router.send_command(:call_once_v, command, &block)
    end

    def call_once_v(command, &block)
      command = @command_builder.generate(command)
      @router.send_command(:call_once_v, command, &block)
    end

    def blocking_call(timeout, *args, **kwargs, &block)
      command = @command_builder.generate(args, kwargs)
      @router.send_command(:blocking_call_v, command, timeout, &block)
    end

    def blocking_call_v(timeout, command, &block)
      command = @command_builder.generate(command)
      @router.send_command(:blocking_call_v, command, timeout, &block)
    end

    def scan(*args, **kwargs, &block)
      raise ArgumentError, 'block required' unless block

      seed = Random.new_seed
      cursor = ZERO_CURSOR_FOR_SCAN
      loop do
        cursor, keys = @router.scan('SCAN', cursor, *args, seed: seed, **kwargs)
        keys.each(&block)
        break if cursor == ZERO_CURSOR_FOR_SCAN
      end
    end

    def sscan(key, *args, **kwargs, &block)
      node = @router.assign_node(['SSCAN', key])
      @router.try_delegate(node, :sscan, key, *args, **kwargs, &block)
    end

    def hscan(key, *args, **kwargs, &block)
      node = @router.assign_node(['HSCAN', key])
      @router.try_delegate(node, :hscan, key, *args, **kwargs, &block)
    end

    def zscan(key, *args, **kwargs, &block)
      node = @router.assign_node(['ZSCAN', key])
      @router.try_delegate(node, :zscan, key, *args, **kwargs, &block)
    end

    def pipelined
      seed = @config.use_replica? && @config.replica_affinity == :random ? nil : Random.new_seed
      pipeline = ::RedisClient::Cluster::Pipeline.new(@router, @command_builder, @concurrent_worker, seed: seed)
      yield pipeline
      return [] if pipeline.empty?

      pipeline.execute
    end

    # Since Redis cluster is sharded by key, the client needs to know the key for selecting the node.
    #
    # @param watch [Array<String>] the watch list of keys
    # @param key [String] the representative key or hashtag
    def multi(watch: nil, key: nil, &block)
      raise ArgumentError, 'watch or key must be provided' if (watch.nil? || watch.empty?) && (key.nil? || key.empty?)

      key = !key.nil? ? key : watch.first
      node_key = @router.find_node_key_by_key(key)
      @router.find_node(node_key).multi(watch: watch, &block)
    end

    def pubsub
      ::RedisClient::Cluster::PubSub.new(@router, @command_builder)
    end

    # You have a responsibility that your command should be affected to the same node.
    # It is failed with an error if you call commands which affect multiple nodes.
    def with(key:, write: true, retry_count: 0, &block)
      raise ArgumentError, 'key must be provided' if key.nil? || key.empty?

      node_key = @router.find_node_key_by_key(key, write: write)
      @router.find_node(node_key).with(retry_count: retry_count, &block)
    end

    def close
      @concurrent_worker.close
      @router.close
      nil
    end

    private

    def method_missing(name, *args, **kwargs, &block)
      if @router.command_exists?(name)
        args.unshift(name)
        command = @command_builder.generate(args, kwargs)
        return @router.send_command(:call_v, command, &block)
      end

      super
    end

    def respond_to_missing?(name, include_private = false)
      return true if @router.command_exists?(name)

      super
    end
  end
end
