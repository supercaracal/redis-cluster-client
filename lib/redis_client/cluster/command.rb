# frozen_string_literal: true

require 'strscan'
require 'redis_client'
require 'redis_client/cluster/errors'
require 'redis_client/cluster/key_slot_converter'

class RedisClient
  class Cluster
    class Command
      EMPTY_STRING = ''
      EMPTY_HASH = {}.freeze
      EMPTY_ARRAY = [].freeze

      private_constant :EMPTY_STRING, :EMPTY_HASH, :EMPTY_ARRAY

      Detail = Struct.new(
        'RedisCommand',
        :first_key_position,
        :last_key_position,
        :key_step,
        :write?,
        :readonly?,
        keyword_init: true
      )

      class << self
        def load(nodes, slow_command_timeout: -1) # rubocop:disable Metrics/AbcSize
          cmd = errors = nil

          nodes&.each do |node|
            regular_timeout = node.read_timeout
            node.read_timeout = slow_command_timeout > 0.0 ? slow_command_timeout : regular_timeout
            reply = node.call('COMMAND')
            node.read_timeout = regular_timeout
            commands = parse_command_reply(reply)
            cmd = ::RedisClient::Cluster::Command.new(commands)
            break
          rescue ::RedisClient::Error => e
            errors ||= []
            errors << e
          end

          return cmd unless cmd.nil?

          raise ::RedisClient::Cluster::InitialSetupError.from_errors(errors)
        end

        private

        def parse_command_reply(rows)
          rows&.each_with_object({}) do |row, acc|
            next if row[0].nil?

            acc[row[0].downcase] = ::RedisClient::Cluster::Command::Detail.new(
              first_key_position: row[3],
              last_key_position: row[4],
              key_step: row[5],
              write?: row[2].include?('write'),
              readonly?: row[2].include?('readonly')
            )
          end.freeze || EMPTY_HASH
        end
      end

      def initialize(commands)
        @commands = commands || EMPTY_HASH
      end

      def extract_first_key(command)
        i = determine_first_key_position(command)
        return EMPTY_STRING if i == 0

        command[i]
      end

      def should_send_to_primary?(command)
        extract_command_info(command&.first)&.write?
      end

      def should_send_to_replica?(command)
        extract_command_info(command&.first)&.readonly?
      end

      def exists?(name)
        name = name.to_s unless name.is_a?(String)
        @commands.key?(name) || @commands.key?(name&.downcase)
      end

      private

      def extract_command_info(name)
        @commands[name] || @commands[name&.downcase]
      end

      def determine_first_key_position(command) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
        return 0 if !command.is_a?(Array) || command.empty?

        name = StringScanner.new(command.first)
        if name.skip(/(get|set|del|mget|mset)/i) # for an optimization
          extract_command_info(command.first)&.first_key_position.to_i
        elsif name.skip(/(eval|evalsha|zinterstore|zunionstore)/i)
          3
        elsif name.skip(/object/i)
          2
        elsif name.skip(/memory/i)
          command[1].to_s.casecmp('usage').zero? ? 2 : 0
        elsif name.skip(/migrate/i)
          command[3].empty? ? determine_optional_key_position(command, 'keys') : 3
        elsif name.skip(/(xread|xreadgroup)/i)
          determine_optional_key_position(command, 'streams')
        else
          extract_command_info(command.first)&.first_key_position.to_i
        end
      end

      def determine_optional_key_position(command, option_name)
        idx = command.map { |e| e.to_s.downcase }.index(option_name&.downcase)
        idx.nil? ? 0 : idx + 1
      end
    end
  end
end
