module MonitorMetrics
  # How the app appears on the wall. Everything is optional; defaults come
  # from the Rails application.
  class AppSettings
    ID_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,62}\z/.freeze

    # Stable identifier (file name in the registry, key in the collector state).
    attr_accessor :id
    # Display name.
    attr_accessor :name
    # Public URL the collector checks through nginx, e.g. "https://iloveradio.es".
    attr_accessor :url
    # Extra host names served by the app (the url host and www. are implied).
    attr_accessor :hosts
    # Local port the app listens on. Detected from Puma / `rails s -p` / PORT when nil.
    attr_accessor :port
    # GNU screen session the app runs in, checked when set.
    attr_accessor :screen
    # Path requested on `url` for the public check.
    attr_accessor :health_path
    # Position on the overview and in the rotation (lower first).
    attr_accessor :order
    # Response time (ms) above which the app turns WARNING. nil = collector default.
    attr_accessor :slow_ms
    # false takes the app off the wall without removing the gem.
    attr_accessor :enabled

    def initialize(config)
      @config = config
      @hosts = []
      @health_path = "/"
      @order = 100
      @enabled = true
    end

    def resolved_id
      raw = id || default_id
      raw.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    def resolved_name
      name || @config.app_name || default_name
    end

    # Hash shared by the registry file and the metrics report.
    def to_h(detected_port = nil, port_source = nil)
      validate!
      {
        "id" => resolved_id,
        "name" => resolved_name,
        "url" => url,
        "hosts" => Array(hosts).map(&:to_s),
        "port" => port ? Integer(port) : detected_port,
        "port_source" => port ? "config" : port_source,
        "screen" => screen,
        "health_path" => health_path,
        "order" => order,
        "slow_ms" => slow_ms,
        "enabled" => enabled ? true : false,
        "metrics_path" => @config.path
      }
    end

    def validate!
      problems = []
      problems << "id #{resolved_id.inspect} must match #{ID_FORMAT.source}" unless resolved_id =~ ID_FORMAT
      problems << "url must start with http:// or https://" if url && url !~ %r{\Ahttps?://[^/\s]+}
      problems << "port must be an integer 1-65535" if port && !(Integer(port, exception: false).to_i.between?(1, 65_535))
      problems << "order must be a number" unless order.is_a?(Numeric)
      problems << "slow_ms must be a positive number" if slow_ms && !(slow_ms.is_a?(Numeric) && slow_ms > 0)
      problems << "health_path must start with /" unless health_path.to_s.start_with?("/")
      raise ArgumentError, "monitor_metrics app settings: #{problems.join('; ')}" unless problems.empty?

      true
    end

    private

    # The Rails module name is stable across display-name changes; outside
    # Rails fall back to the name.
    def default_id
      return underscore(module_name) if module_name

      name || @config.app_name || "app"
    end

    def default_name
      module_name || "App"
    end

    def module_name
      return nil unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application

      ::Rails.application.class.name.split("::").first
    end

    def underscore(text)
      text.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
