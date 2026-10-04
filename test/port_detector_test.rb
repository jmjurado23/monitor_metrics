require "test_helper"

class PortDetectorTest < Minitest::Test
  def detector(**kw)
    defaults = { argv: [], env: {}, rails_server_options: nil, puma_binds: [] }
    MonitorMetrics::PortDetector.new(**defaults.merge(kw))
  end

  def test_rails_server_options_first
    d = detector(rails_server_options: { Port: 3004 }, puma_binds: ["tcp://0.0.0.0:9292"], env: { "PORT" => "1" })
    assert_equal [3004, "rails_server"], d.detect
  end

  def test_puma_bind
    assert_equal [3002, "puma"], detector(puma_binds: ["unix:///tmp/s.sock", "tcp://127.0.0.1:3002"]).detect
  end

  def test_argv_forms
    assert_equal [3001, "argv"], detector(argv: ["server", "-p", "3001"]).detect
    assert_equal [3005, "argv"], detector(argv: ["--port=3005"]).detect
    assert_equal [3006, "argv"], detector(argv: ["-p3006"]).detect
  end

  def test_env_port_last
    assert_equal [5000, "env"], detector(env: { "PORT" => "5000" }).detect
  end

  def test_nothing_or_garbage
    assert_equal [nil, nil], detector(env: { "PORT" => "abc" }, argv: ["-p", "99999"]).detect
  end

  def test_server_process
    assert detector(puma_binds: ["tcp://0.0.0.0:3000"]).server_process?
    assert detector(rails_server_options: { Port: 3000 }).server_process?
    refute detector(env: { "PORT" => "3000" }).server_process?   # console with PORT set
  end
end
