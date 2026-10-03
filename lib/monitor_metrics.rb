require "json"
require "time"

require "monitor_metrics/version"
require "monitor_metrics/metric"
require "monitor_metrics/configuration"
require "monitor_metrics/buckets"
require "monitor_metrics/database"
require "monitor_metrics/report"
require "monitor_metrics/middleware"

# Exposes an app's health and business metrics as JSON at a private endpoint
# (/internal/metrics by default) so the server-side collector can read them.
#
#   MonitorMetrics.configure do |c|
#     c.metric :users_today, label: "Sign-ups today" do
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
