require "test_helper"

class PortDetectorTest < Minitest::Test
  NONE = { "tcp" => [], "unix" => [] }.freeze

  def detector(**kw)
    defaults = { argv: [], env: {}, rails_server_options: nil, puma_binds: [], listeners: NONE }
    MonitorMetrics::PortDetector.new(**defaults.merge(kw))
  end

  def test_real_listeners_win
    d = detector(listeners: { "tcp" => [3000], "unix" => ["/tmp/cooking.socket"] },
                 puma_binds: ["tcp://0.0.0.0:9292"], env: { "PORT" => "1" })
    assert_equal({ "port" => 3000, "socket" => "/tmp/cooking.socket", "source" => "listening",
                   "listeners" => { "tcp" => [3000], "unix" => ["/tmp/cooking.socket"] } }, d.detect)
  end

  def test_unix_socket_only
    r = detector(listeners: { "tcp" => [], "unix" => ["/tmp/iloveradio.socket"] }).detect
    assert_nil r["port"]
    assert_equal "/tmp/iloveradio.socket", r["socket"]
  end

  # `rails s` always reports Port 3000; it must not be taken as the address.
  def test_rails_server_default_port_is_ignored
    r = detector(rails_server_options: { Port: 3000 }).detect
    assert_nil r["port"]
    assert_nil r["source"]
  end

  def test_puma_binds_tcp_and_unix
    r = detector(puma_binds: ["unix:///tmp/make.socket", "tcp://127.0.0.1:3002"]).detect
    assert_equal [3002, "/tmp/make.socket", "puma"], r.values_at("port", "socket", "source")
  end

  def test_argv_forms
    assert_equal [3001, "argv"], detector(argv: ["server", "-p", "3001"]).detect.values_at("port", "source")
    assert_equal 3005, detector(argv: ["--port=3005"]).detect["port"]
    assert_equal 3006, detector(argv: ["-p3006"]).detect["port"]
  end

  def test_env_port_last
    assert_equal [5000, "env"], detector(env: { "PORT" => "5000" }).detect.values_at("port", "source")
  end

  def test_nothing_or_garbage
    r = detector(env: { "PORT" => "abc" }, argv: ["-p", "99999"]).detect
    assert_equal [nil, nil, nil], r.values_at("port", "socket", "source")
  end

  def test_server_process
    assert detector(puma_binds: ["tcp://0.0.0.0:3000"]).server_process?
    assert detector(rails_server_options: { Port: 3000 }).server_process?
    refute detector(env: { "PORT" => "3000" }).server_process?   # console with PORT set
  end
end
