# frozen_string_literal: true

class RedisClient
  class Cluster
    module ConcurrentWorker
      # This class is just an experimental implementation. There are some bugs for race condition.
      # Ruby VM allocates 1 MB memory as a stack for a thread.
      # It is a fixed size but we can modify the size with some environment variables.
      # So it consumes memory 1 MB multiplied a number of workers.
      class Pooled
        def initialize
          @q = Queue.new
          size = ::RedisClient::Cluster::ConcurrentWorker::MAX_WORKERS
          size = size.positive? ? size : 5
          @workers = Array.new(size)
        end

        def new_group(size:)
          raise ArgumentError, "size must be positive: #{size} given" unless size.positive?

          ensure_workers if @workers.first.nil?
          ::RedisClient::Cluster::ConcurrentWorker::Group.new(worker: self, size: size)
        end

        def push(task)
          @q << task
        end

        def close
          @q.clear
          @workers.each { |t| t&.exit }
          @workers.clear
          @q.close
          nil
        end

        private

        def ensure_workers
          @workers.size.times do |i|
            @workers[i] = spawn_worker unless @workers[i]&.alive?
          end
        end

        def spawn_worker
          Thread.new(@q) do |q|
            loop { q.pop.exec }
          end
        end
      end
    end
  end
end