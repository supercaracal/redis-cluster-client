# frozen_string_literal: true

require 'redis_client/command_builder'

class RedisClient
  class Cluster
    module CommandBuilder
      extend ::RedisClient::CommandBuilder
      extend self # rubocop:disable Style/ModuleFunction

      def generate(args, kwargs = nil)
        super.tap do |command|
          if command.first.frozen?
            command[0] = command.first.downcase
          else
            command.first.downcase!
          end
        end
      end
    end
  end
end
