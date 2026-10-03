require "rack/utils"

module MonitorMetrics
  # Answers MonitorMetrics.config.path; every other request passes straight
  # through. Anything not authorized gets a bare 404 so the endpoint does not
  # advertise itself.
  class Middleware
    NOT_FOUND = [404, { "content-type" => "text/plain" }, ["Not Found"]].freeze
    PROXY_HEADERS = %w[HTTP_X_FORWARDED_FOR HTTP_X_REAL_IP HTTP_FORWARDED].freeze

    def initialize(app, config = nil)
      @app = app
      @config = config
    end

    def call(env)
      config = @config || MonitorMetrics.config
      return @app.call(env) unless env["PATH_INFO"] == config.path
      return not_found unless %w[GET HEAD].include?(env["REQUEST_METHOD"])
      return not_found unless authorized?(env, config)

      body = JSON.generate(Report.new(config).build)
      [200, { "content-type" => "application/json", "cache-control" => "no-store" }, [body]]
    rescue StandardError => e
      error = JSON.generate("error" => "#{e.class}: #{e.message}"[0, 300])
      [500, { "content-type" => "application/json", "cache-control" => "no-store" }, [error]]
    end

    private

    def authorized?(env, config)
      expected = config.resolved_token
      return false if expected.nil?

      allowed = config.allowed_ips
      return false if allowed && !allowed.empty? && !allowed.include?(env["REMOTE_ADDR"])
      return false if config.reject_proxied && PROXY_HEADERS.any? { |h| env[h] }

      provided = env["HTTP_X_MONITOR_TOKEN"] || bearer(env["HTTP_AUTHORIZATION"])
      return false if provided.nil?

      Rack::Utils.secure_compare(expected, provided)
    end

    def bearer(header)
      return nil unless header

      match = header.match(/\ABearer\s+(.+)\z/)
      match && match[1].strip
    end

    def not_found
      [NOT_FOUND[0], NOT_FOUND[1].dup, NOT_FOUND[2].dup]
    end
  end
end
