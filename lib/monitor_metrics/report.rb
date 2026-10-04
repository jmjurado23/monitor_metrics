module MonitorMetrics
  # Builds the JSON document served at the metrics endpoint.
  class Report
    def initialize(config)
      @config = config
    end

    def build(now = Time.now)
      within_rails_executor do
        {
          "schema" => SCHEMA,
          "gem_version" => VERSION,
          "generated_at" => now.utc.iso8601,
          "monitor" => monitor_info,
          "app" => app_info(now),
          "databases" => @config.check_databases ? Database.check : [],
          "metrics" => @config.metrics.map { |m| m.evaluate(now) }
        }
      end
    end

    private

    # The middleware sits in front of the Rails stack, so wrap the work in the
    # executor: it checks ActiveRecord connections back in and enables the
    # query cache exactly like a normal request would.
    def within_rails_executor(&block)
      app = defined?(::Rails) && ::Rails.respond_to?(:application) ? ::Rails.application : nil
      return yield unless app && app.respond_to?(:executor)

      app.executor.wrap(&block)
    end

    def monitor_info
      port, source = Report.detected_port
      @config.app.to_h(port, source)
    end

    def app_info(now)
      {
        "name" => app_name,
        "env" => rails_env,
        "rails" => defined?(::Rails::VERSION) ? ::Rails::VERSION::STRING : nil,
        "ruby" => RUBY_VERSION,
        "pid" => Process.pid,
        "booted_at" => BOOTED_AT.utc.iso8601,
        "uptime_s" => (now - BOOTED_AT).to_i,
        "rss_mb" => rss_mb,
        "threads" => Thread.list.size,
        "revision" => Report.revision
      }
    end

    def app_name
      @config.app.resolved_name
    end

    def rails_env
      return ::Rails.env.to_s if defined?(::Rails) && ::Rails.respond_to?(:env)

      ENV["RACK_ENV"]
    end

    def rss_mb
      line = File.foreach("/proc/self/status").find { |l| l.start_with?("VmRSS:") }
      line ? (line.split[1].to_i / 1024.0).round(1) : nil
    rescue SystemCallError
      nil
    end

    class << self
      # Port detection walks ObjectSpace once; the answer cannot change later.
      def detected_port
        @detected_port ||= PortDetector.new.detect
      end

      def reset_port!
        @detected_port = nil
      end

      # Deployed git SHA, resolved once per process.
      def revision
        return @revision if defined?(@revision)

        @revision = resolve_revision
      end

      private

      def resolve_revision
        return ENV["REVISION"][0, 12] if ENV["REVISION"] && !ENV["REVISION"].empty?

        root = defined?(::Rails) && ::Rails.respond_to?(:root) && ::Rails.root ? ::Rails.root.to_s : Dir.pwd
        file = File.join(root, "REVISION")
        return File.read(file).strip[0, 12] if File.file?(file)

        sha = IO.popen(["git", "-C", root, "rev-parse", "--short", "HEAD"], err: File::NULL, &:read).to_s.strip
        sha.empty? ? nil : sha
      rescue StandardError
        nil
      end
    end
  end
end
