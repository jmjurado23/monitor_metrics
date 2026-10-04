require "fileutils"

module MonitorMetrics
  # Writes ~/.wallmon/apps.d/<id>.json when the app boots as a server, so the
  # collector knows the app exists (and its port) even while it is down.
  module Registry
    module_function

    # Called from the Railtie. Never raises: monitoring must not break a boot.
    def register_if_server(config = MonitorMetrics.config, detector = PortDetector.new, env: rails_env)
      reason = skip_reason(config, detector, env)
      return log("not registering: #{reason}") if reason

      path = write(config, detector)
      log("registered #{path}")
      path
    rescue StandardError => e
      log("registration failed: #{e.class}: #{e.message}", :warn)
      nil
    end

    def skip_reason(config, detector, env)
      flag = ENV["MONITOR_METRICS_REGISTER"]
      return "MONITOR_METRICS_REGISTER=0" if flag == "0"
      return nil if flag == "1"
      return "environment #{env} not in register_environments" unless config.register_environments.include?(env.to_s)
      return "not a server process" unless detector.server_process?

      nil
    end

    def write(config, detector = PortDetector.new)
      port, source = detector.detect
      entry = config.app.to_h(port, source).merge(
        "schema" => SCHEMA,
        "gem_version" => VERSION,
        "root" => app_root,
        "pid" => Process.pid,
        "registered_at" => Time.now.utc.iso8601
      )
      dir = config.resolved_registry_dir
      FileUtils.mkdir_p(dir, mode: 0o700)
      path = File.join(dir, "#{entry['id']}.json")
      tmp = "#{path}.tmp.#{Process.pid}"
      File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(JSON.pretty_generate(entry)) }
      File.rename(tmp, path)
      path
    end

    def app_root
      defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root ? ::Rails.root.to_s : Dir.pwd
    end

    def rails_env
      defined?(::Rails) && ::Rails.respond_to?(:env) ? ::Rails.env.to_s : (ENV["RACK_ENV"] || "development")
    end

    def log(message, level = :info)
      logger = defined?(::Rails) && ::Rails.respond_to?(:logger) ? ::Rails.logger : nil
      logger ? logger.public_send(level, "[monitor_metrics] #{message}") : nil
    end
  end
end
