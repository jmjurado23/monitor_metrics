module MonitorMetrics
  class Railtie < ::Rails::Railtie
    # Position 0, ahead of ActionDispatch::SSL (force_ssl would redirect the
    # collector's plain-HTTP localhost call) and HostAuthorization (Rails 6+
    # would reject the 127.0.0.1 Host header).
    initializer "monitor_metrics.middleware" do |app|
      app.middleware.insert_before 0, MonitorMetrics::Middleware
    end

    # After initializers have run, so `c.app` settings from
    # config/initializers/monitor_metrics.rb are in place.
    config.after_initialize do
      MonitorMetrics::Registry.register_if_server
    end
  end
end
