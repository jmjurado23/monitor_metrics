require "json"
require "time"

require "monitor_metrics/version"
require "monitor_metrics/metric"
require "monitor_metrics/app_settings"
require "monitor_metrics/listeners"
require "monitor_metrics/port_detector"
require "monitor_metrics/configuration"
require "monitor_metrics/buckets"
require "monitor_metrics/database"
require "monitor_metrics/report"
require "monitor_metrics/registry"
require "monitor_metrics/middleware"

# Exposes an app's health and business metrics as JSON at a private endpoint
# (/internal/metrics by default) so the server-side collector can read them,
# and registers the app in ~/.wallmon/apps.d at boot so the collector finds it.
#
#   MonitorMetrics.configure do |c|
#     c.app { |a| a.name = "Cocina Tradicional"; a.url = "https://cocina-tradicional.es" }
#     c.metric :users_today, label: "Sign-ups today", overview: true do
#       User.where(:created_at.gte => Time.now.beginning_of_day).count
#     end
#   end
#
# NOTE: keep this gem Ruby 2.7 compatible (no hash shorthand, endless methods,
# `it`, Hash#except...). The oldest app using it runs Rails 5.2 / Ruby 2.7.
module MonitorMetrics
  BOOTED_AT = Time.now

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
      config
    end

    # Test helper.
    def reset!
      @config = Configuration.new
    end
  end
end

require "monitor_metrics/railtie" if defined?(::Rails::Railtie)
