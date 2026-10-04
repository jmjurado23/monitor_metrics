module MonitorMetrics
  class Configuration
    # URL path the middleware answers on. Everything else passes through.
    attr_accessor :path
    # Shared secret. When nil, falls back to ENV["MONITOR_METRICS_TOKEN"], then
    # to the file at ENV["MONITOR_METRICS_TOKEN_FILE"] or ~/.monitor_metrics_token.
    # With no token anywhere the endpoint stays disabled (answers 404).
    attr_accessor :token
    # Only these REMOTE_ADDRs may ask. nil or [] allows any address.
    attr_accessor :allowed_ips
    # nginx proxies public traffic from 127.0.0.1 too, so a localhost check alone
    # lets the internet through. Requests carrying proxy headers are refused.
    attr_accessor :reject_proxied
    # Seconds a metric value is cached before its block runs again.
    attr_accessor :default_ttl
    # Kept for v0.1 initializers; prefer `c.app { |a| a.name = ... }`.
    attr_accessor :app_name
    # Set to false to skip the automatic ActiveRecord / Mongoid ping.
    attr_accessor :check_databases
    # Folder where each app registers itself at boot so the collector finds it
    # (default ~/.wallmon/apps.d, or ENV["MONITOR_METRICS_REGISTRY"]).
    attr_accessor :registry_dir
    # Rails environments that register. The endpoint works in every environment.
    attr_accessor :register_environments

    attr_reader :metrics

    def initialize
      @path = "/internal/metrics"
      @token = nil
      @allowed_ips = ["127.0.0.1", "::1"]
      @reject_proxied = true
      @default_ttl = 60
      @app_name = nil
      @check_databases = true
      @registry_dir = nil
      @register_environments = %w[production]
      @metrics = []
      @app = AppSettings.new(self)
    end

    # How this app appears on the wall: id, name, url, port, order...
    #
    #   c.app do |a|
    #     a.name = "Cocina Tradicional"
    #     a.url  = "https://cocina-tradicional.es"
    #   end
    def app
      yield @app if block_given?
      @app
    end

    def resolved_registry_dir
      dir = registry_dir || ENV["MONITOR_METRICS_REGISTRY"]
      dir = File.join(Dir.home, ".wallmon", "apps.d") if blank?(dir)
      File.expand_path(dir)
    end

    # Declares a metric. The block runs at most once per `ttl` seconds.
    #
    #   type: :number  -> block returns a Numeric
    #   type: :series  -> block returns [[time, value], ...] or { time => value }
    #   type: :table   -> block returns [{ "col" => val }, ...]
    #   type: :text    -> block returns anything responding to #to_s
    #
    # Display options: overview: true, hidden: true. Alarm thresholds (numbers):
    # warn_above:, critical_above:, warn_below:, critical_below:.
    def metric(key, label: nil, type: :number, unit: nil, ttl: nil, **options, &block)
      raise ArgumentError, "metric #{key.inspect} needs a block" unless block

      metric = Metric.new(key.to_s, label || humanize(key), type, unit, ttl || default_ttl, block, options)
      @metrics.reject! { |m| m.key == metric.key }
      @metrics << metric
      metric
    end

    def resolved_token
      value = token.respond_to?(:call) ? token.call : token
      return value.to_s unless blank?(value)

      env = ENV["MONITOR_METRICS_TOKEN"]
      return env unless blank?(env)

      file = ENV["MONITOR_METRICS_TOKEN_FILE"]
      file = File.join(Dir.home, ".monitor_metrics_token") if blank?(file)
      return nil unless File.file?(file)

      from_file = File.read(file).strip
      blank?(from_file) ? nil : from_file
    rescue ArgumentError, SystemCallError
      # Dir.home raises without HOME; unreadable file. Either way: disabled.
      nil
    end

    private

    def humanize(key)
      text = key.to_s.tr("_", " ")
      text[0] = text[0].upcase unless text.empty?
      text
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
