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

  def server
    MonitorMetrics::PortDetector.new(argv: [], env: {}, rails_server_options: nil, puma_binds: ["tcp://0.0.0.0:3003"])
  end

  def console
    MonitorMetrics::PortDetector.new(argv: [], env: {}, rails_server_options: nil, puma_binds: [])
  end

  def test_server_in_production_writes_private_file
    path = MonitorMetrics::Registry.register_if_server(MonitorMetrics.config, server, env: "production")
    assert_equal File.join(@dir, "apps.d", "iloveradio.json"), path
    entry = JSON.parse(File.read(path))
    assert_equal "I Love Radio", entry["name"]
    assert_equal 3003, entry["port"]
    assert_equal "puma", entry["port_source"]
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
end
