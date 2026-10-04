require "test_helper"
require "tmpdir"

class RegistryTest < Minitest::Test
  def setup
    MonitorMetrics.reset!
    @dir = Dir.mktmpdir
    MonitorMetrics.configure do |c|
      c.registry_dir = File.join(@dir, "apps.d")
      c.app do |a|
        a.id = "iloveradio"
        a.name = "I Love Radio"
        a.url = "https://iloveradio.es"
      end
    end
    @saved_flag = ENV.delete("MONITOR_METRICS_REGISTER")
  end

  def teardown
    FileUtils.remove_entry(@dir)
    @saved_flag ? ENV["MONITOR_METRICS_REGISTER"] = @saved_flag : ENV.delete("MONITOR_METRICS_REGISTER")
  end

  NONE = { "tcp" => [], "unix" => [] }.freeze

  def server(listeners = { "tcp" => [3003], "unix" => [] })
    MonitorMetrics::PortDetector.new(argv: [], env: {}, rails_server_options: nil,
                                     puma_binds: ["tcp://0.0.0.0:3003"], listeners: listeners)
  end

  def console
    MonitorMetrics::PortDetector.new(argv: [], env: {}, rails_server_options: nil, puma_binds: [], listeners: NONE)
  end

  # Before Puma binds: `rails s` process with no listeners yet, then a socket appears.
  class LateBinding
    def initialize(after)
      @calls = 0
      @after = after
    end

    def server_process?
      true
    end

    def detect
      @calls += 1
      live = @calls > @after ? { "tcp" => [], "unix" => ["/tmp/iloveradio.socket"] } : { "tcp" => [], "unix" => [] }
      source = live["unix"].empty? ? nil : "listening"
      { "port" => nil, "socket" => live["unix"].first, "source" => source, "listeners" => live }
    end
  end

  def test_server_in_production_writes_private_file
    path = MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, server, env: "production")
    assert_equal File.join(@dir, "apps.d", "iloveradio.json"), path
    entry = JSON.parse(File.read(path))
    assert_equal "I Love Radio", entry["name"]
    assert_equal 3003, entry["port"]
    assert_equal "listening", entry["port_source"]
    assert_equal 2, entry["schema"]
    assert_equal Process.pid, entry["pid"]
    assert_equal "600", format("%o", File.stat(path).mode & 0o777)
    assert_equal "700", format("%o", File.stat(File.dirname(path)).mode & 0o777)
    assert_empty Dir[File.join(@dir, "apps.d", "*.tmp.*")]
  end

  def test_console_and_other_envs_do_not_register
    assert_nil MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, console, env: "production")
    assert_nil MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, server, env: "development")
    refute File.exist?(File.join(@dir, "apps.d"))
  end

  def test_env_flag_overrides
    ENV["MONITOR_METRICS_REGISTER"] = "1"
    assert MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, console, env: "development")
    ENV["MONITOR_METRICS_REGISTER"] = "0"
    assert_nil MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, server, env: "production")
  end

  def test_invalid_settings_do_not_raise
    MonitorMetrics.config.app.url = "not a url"
    assert_nil MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, server, env: "production")
  end

  def test_entry_is_rewritten_once_the_server_listens
    detector = LateBinding.new(3)
    path = MonitorMetrics::Registry.write(MonitorMetrics.config, detector)
    assert_nil JSON.parse(File.read(path))["socket"]
    assert_equal path, MonitorMetrics::Registry.wait_for_listeners(MonitorMetrics.config, detector, attempts: 5, interval: 0)
    entry = JSON.parse(File.read(path))
    assert_equal "/tmp/iloveradio.socket", entry["socket"]
    assert_equal "listening", entry["port_source"]
  end

  def test_gives_up_quietly_when_nothing_listens
    assert_nil MonitorMetrics::Registry.wait_for_listeners(MonitorMetrics.config, LateBinding.new(99), attempts: 3, interval: 0)
  end
end
