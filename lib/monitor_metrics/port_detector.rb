module MonitorMetrics
  # Works out where the collector can reach this app, so nobody repeats it in
  # the collector config. Sources, most reliable first:
  #
  #   listening  sockets the process really listens on (Linux /proc), once bound
  #   puma       binds of the `puma` CLI (tcp:// and unix://)
  #   argv       -p 3000 / --port=3000 on the command line
  #   env        ENV["PORT"]
  #
  # `rails server` options are deliberately not used for the address: they
  # report Port 3000 by default even when config/puma.rb binds a Unix socket.
  #
  # #detect returns { "port", "socket", "source", "listeners" }.
  class PortDetector
    def initialize(argv: ARGV, env: ENV, rails_server_options: :auto, puma_binds: :auto, listeners: :auto)
      @argv = argv
      @env = env
      @rails_server_options = rails_server_options
      @puma_binds = puma_binds
      @listeners = listeners
    end

    def detect
      live = listeners
      return result(live["tcp"].first, live["unix"].first, "listening", live) if any?(live)

      binds = parsed_binds
      return result(binds["tcp"].first, binds["unix"].first, "puma", live) if any?(binds)

      port = safely { from_argv }
      return result(port, nil, "argv", live) if port

      port = safely { valid(@env["PORT"]) }
      return result(port, nil, "env", live) if port

      result(nil, nil, nil, live)
    end

    # True when this process is serving HTTP (not a console, rake or runner).
    def server_process?
      !rails_server_options.nil? || !puma_binds.empty?
    end

    private

    def result(port, socket, source, live)
      { "port" => port, "socket" => socket, "source" => source, "listeners" => live }
    end

    def any?(found)
      !(found["tcp"].empty? && found["unix"].empty?)
    end

    def safely
      yield
    rescue StandardError
      nil
    end

    def listeners
      return @listeners unless @listeners == :auto

      Listeners.current
    end

    def parsed_binds
      found = Listeners.empty
      puma_binds.each do |bind|
        bind = bind.to_s
        if (m = bind.match(%r{\Atcp://[^/]*:(\d+)})) && (port = valid(m[1]))
          found["tcp"] << port
        elsif (m = bind.match(%r{\Aunix://(/[^?]+)}))
          found["unix"] << m[1]
        end
      end
      found
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
