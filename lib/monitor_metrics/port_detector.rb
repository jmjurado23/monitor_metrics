module MonitorMetrics
  # Finds the local port the app serves on, so nobody has to repeat it in the
  # collector config. Sources, most reliable first:
  #
  #   rails_server  options of the running `rails server` (-p / --port)
  #   puma          bind of the `puma` CLI (config/puma.rb, -p, -b)
  #   argv          -p 3000 / --port=3000 on the command line
  #   env           ENV["PORT"]
  #
  # Returns [port, source] or [nil, nil].
  class PortDetector
    def initialize(argv: ARGV, env: ENV, rails_server_options: :auto, puma_binds: :auto)
      @argv = argv
      @env = env
      @rails_server_options = rails_server_options
      @puma_binds = puma_binds
    end

    def detect
      [
        ["rails_server", -> { from_rails_server }],
        ["puma", -> { from_binds }],
        ["argv", -> { from_argv }],
        ["env", -> { valid(@env["PORT"]) }]
      ].each do |source, finder|
        port = begin
          finder.call
        rescue StandardError
          nil
        end
        return [port, source] if port
      end
      [nil, nil]
    end

    # True when this process is serving HTTP (not a console, rake or runner).
    def server_process?
      !rails_server_options.nil? || !puma_binds.empty?
    end

    private

    def from_rails_server
      opts = rails_server_options
      opts && valid(opts[:Port] || opts["Port"] || opts[:port])
    end

    def from_binds
      puma_binds.each do |bind|
        match = bind.to_s.match(%r{\Atcp://[^/]*:(\d+)})
        port = match && valid(match[1])
        return port if port
      end
      nil
    end

    def from_argv
      @argv.each_with_index do |arg, i|
        case arg
        when "-p", "--port" then return valid(@argv[i + 1])
        when /\A--port=(\d+)\z/, /\A-p(\d+)\z/ then return valid(Regexp.last_match(1))
        end
      end
      nil
    end

    def valid(value)
      port = Integer(value.to_s, 10)
      port.between?(1, 65_535) ? port : nil
    rescue ArgumentError, TypeError
      nil
    end

    def rails_server_options
      return @rails_server_options unless @rails_server_options == :auto
      return nil unless defined?(::Rails::Server)

      server = ObjectSpace.each_object(::Rails::Server).first
      server && server.respond_to?(:options) ? server.options : nil
    end

    # Puma.cli_config is only set by the `puma` executable, never by Bundler
    # merely loading the gem, so a console does not count as a server.
    def puma_binds
      return Array(@puma_binds) unless @puma_binds == :auto
      return [] unless defined?(::Puma) && ::Puma.respond_to?(:cli_config) && ::Puma.cli_config

      Array(::Puma.cli_config.options[:binds])
    end
  end
end
