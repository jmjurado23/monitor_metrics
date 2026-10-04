module MonitorMetrics
  # The sockets this process is really listening on, read from Linux /proc.
  # Unlike `rails server` options (which always say 3000) this reflects what
  # Puma actually bound: TCP ports and/or Unix sockets such as /tmp/app.socket.
  #
  #   Listeners.current  # => { "tcp" => [3000], "unix" => ["/tmp/cooking.socket"] }
  #
  # Returns empty lists on non-Linux systems or before the server has bound.
  module Listeners
    ACCEPTING = 0x10000 # __SO_ACCEPTCON: a listening Unix socket
    TCP_LISTEN = "0A"
    # Puma's control server (`activate_control_app`, and `rails s` on Puma 3)
    # listens on /tmp/puma-status-<time>-<pid>; it is not the app.
    CONTROL_SOCKET = %r{/puma-status-[^/]*\z}.freeze

    module_function

    def current(fd_dir: "/proc/self/fd", net_dir: "/proc/net")
      inodes = socket_inodes(fd_dir)
      return empty if inodes.empty?

      tcp = (tcp_ports(File.join(net_dir, "tcp"), inodes) + tcp_ports(File.join(net_dir, "tcp6"), inodes)).uniq.sort
      { "tcp" => tcp, "unix" => unix_paths(File.join(net_dir, "unix"), inodes).uniq.sort }
    rescue SystemCallError, IOError
      empty
    end

    def empty
      { "tcp" => [], "unix" => [] }
    end

    def socket_inodes(fd_dir)
      Dir.entries(fd_dir).each_with_object({}) do |entry, found|
        next if entry.start_with?(".")

        target = begin
          File.readlink(File.join(fd_dir, entry))
        rescue SystemCallError
          next
        end
        match = target.match(/\Asocket:\[(\d+)\]\z/)
        found[match[1]] = true if match
      end
    end

    # /proc/net/tcp: "sl local_address rem_address st ... uid timeout inode ..."
    def tcp_ports(path, inodes)
      return [] unless File.readable?(path)

      File.readlines(path).drop(1).each_with_object([]) do |line, ports|
        fields = line.split
        next unless fields[3] == TCP_LISTEN && inodes[fields[9]]

        ports << fields[1].split(":").last.to_i(16)
      end
    end

    # /proc/net/unix: "Num RefCount Protocol Flags Type St Inode Path"
    def unix_paths(path, inodes)
      return [] unless File.readable?(path)

      File.readlines(path).drop(1).each_with_object([]) do |line, paths|
        fields = line.split
        next unless fields.size >= 8 && inodes[fields[6]]
        next unless (fields[3].to_i(16) & ACCEPTING) != 0
        next if fields[7].start_with?("@") # abstract namespace, not a file
        next if fields[7] =~ CONTROL_SOCKET

        paths << fields[7]
      end
    end
  end
end
