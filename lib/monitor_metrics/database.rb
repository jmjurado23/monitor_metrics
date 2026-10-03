module MonitorMetrics
  # Pings whichever ORMs the app has loaded. Apps here use either ActiveRecord
  # (PostgreSQL) or Mongoid (MongoDB), both running in Docker on the host.
  module Database
    module_function

    def check
      results = []
      results << probe("activerecord") { active_record_ping } if active_record?
      results << probe("mongodb") { ::Mongoid.default_client.database.command(ping: 1) } if mongoid?
      results
    end

    def active_record?
      return false unless defined?(::ActiveRecord::Base)

      configs = ::ActiveRecord::Base.configurations
      !(configs.respond_to?(:empty?) && configs.empty?)
    end

    def mongoid?
      defined?(::Mongoid) && ::Mongoid.respond_to?(:default_client)
    end

    def active_record_ping
      ::ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.select_value("SELECT 1")
        conn.adapter_name
      end
    end

    def probe(name)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      detail = nil
      error = nil
      begin
        result = yield
        detail = result if result.is_a?(String)
      rescue StandardError => e
        error = "#{e.class}: #{e.message}"[0, 300]
      end
      {
        "name" => detail ? detail.downcase : name,
        "ok" => error.nil?,
        "ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1),
        "error" => error
      }
    end
  end
end
