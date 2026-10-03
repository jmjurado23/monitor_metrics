module MonitorMetrics
  class Railtie < ::Rails::Railtie
    # Position 0, ahead of ActionDispatch::SSL (force_ssl would redirect the
    # collector's plain-HTTP localhost call) and HostAuthorization (Rails 6+
    # would reject the 127.0.0.1 Host header).
    initializer "monitor_metrics.middleware" do |app|
      app.middleware.insert_before 0, MonitorMetrics::Middleware
    end
  end
end
