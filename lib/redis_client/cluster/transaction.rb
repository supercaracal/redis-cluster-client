# frozen_string_literal: true

require 'redis_client'

class RedisClient
  class Cluster
    class Transaction
      ConsistencyError = Class.new(::RedisClient::Error) # TODO: remove
    end
  end
end
