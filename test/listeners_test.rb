require "test_helper"
require "tmpdir"

class ListenersTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @fd = File.join(@root, "fd")
    @net = File.join(@root, "net")
    Dir.mkdir(@fd)
    Dir.mkdir(@net)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def fd(num, target)
    File.symlink(target, File.join(@fd, num.to_s))
  end

  def write(name, body)
    File.write(File.join(@net, name), body)
  end

  TCP_HEADER = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n".freeze

  def test_reads_own_tcp_and_unix_listeners_only
    fd(3, "socket:[111]")   # tcp 0.0.0.0:3000 listening (ours)
    fd(4, "socket:[222]")   # unix /tmp/cooking.socket listening (ours)
    fd(5, "socket:[333]")   # unix connected client socket (ours, not listening)
    fd(6, "/dev/null")
    fd(7, "socket:[555]")   # puma control socket (ours, must be ignored)
    write("tcp", TCP_HEADER +
      "   0: 00000000:0BB8 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 111 1 x\n" \
      "   1: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 999 1 x\n" \
      "   2: 0100007F:0BB8 0100007F:D431 01 00000000:00000000 00:00000000 00000000  1000        0 111 1 x\n")
    write("tcp6", TCP_HEADER)
    write("unix", "Num       RefCount Protocol Flags    Type St Inode Path\n" \
      "0000000000000000: 00000002 00000000 00010000 0001 01 222 /tmp/cooking.socket\n" \
      "0000000000000000: 00000003 00000000 00000000 0001 03 333 /tmp/cooking.socket\n" \
      "0000000000000000: 00000002 00000000 00010000 0001 01 444 /tmp/other-app.socket\n" \
      "0000000000000000: 00000002 00000000 00010000 0001 01 222 @abstract\n" \
      "0000000000000000: 00000002 00000000 00010000 0001 01 555 /tmp/puma-status-1791134119943-89396\n")
    found = MonitorMetrics::Listeners.current(fd_dir: @fd, net_dir: @net)
    assert_equal({ "tcp" => [3000], "unix" => ["/tmp/cooking.socket"] }, found)
  end

  def test_missing_proc_is_empty
    assert_equal MonitorMetrics::Listeners.empty,
                 MonitorMetrics::Listeners.current(fd_dir: File.join(@root, "nope"), net_dir: @net)
  end

  def test_real_proc_does_not_raise
    found = MonitorMetrics::Listeners.current
    assert_kind_of Array, found["tcp"]
    assert_kind_of Array, found["unix"]
  end
end
