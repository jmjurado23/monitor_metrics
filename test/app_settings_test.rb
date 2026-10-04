require "test_helper"

class AppSettingsTest < Minitest::Test
  def setup
    MonitorMetrics.reset!
  end

  def settings
    MonitorMetrics.config.app
  end

  def test_block_sets_fields_and_defaults_fill_the_rest
    MonitorMetrics.configure do |c|
      c.app do |a|
        a.name = "Cocina Tradicional"
        a.url = "https://cocina-tradicional.es"
        a.hosts = ["cocina.example"]
        a.order = 1
      end
    end
    h = settings.to_h("port" => 3002, "socket" => nil, "source" => "puma",
                      "listeners" => { "tcp" => [3002], "unix" => [] })
    assert_equal "cocina_tradicional", h["id"]        # no Rails here: from the name
    assert_equal "Cocina Tradicional", h["name"]
    assert_equal ["cocina.example"], h["hosts"]
    assert_equal 3002, h["port"]
    assert_equal "puma", h["port_source"]
    assert_equal({ "tcp" => [3002], "unix" => [] }, h["listeners"])
    assert_equal "/", h["health_path"]
    assert_equal true, h["enabled"]
  end

  def test_explicit_port_wins_over_detected
    settings.port = "3004"
    h = settings.to_h("port" => 3000, "source" => "env")
    assert_equal 3004, h["port"]
    assert_equal "config", h["port_source"]
  end

  def test_explicit_socket
    settings.socket = "/tmp/iloveradio.socket"
    h = settings.to_h("port" => nil, "socket" => "/tmp/other.socket", "source" => "listening")
    assert_equal "/tmp/iloveradio.socket", h["socket"]
    assert_equal "config", h["port_source"]
    settings.socket = "tmp/relative.socket"
    assert_raises(ArgumentError) { settings.to_h }
  end

  def test_id_is_normalized
    settings.id = "Make Your App"
    assert_equal "make_your_app", settings.resolved_id
  end

  def test_legacy_app_name_still_used
    MonitorMetrics.config.app_name = "Old Name"
    assert_equal "Old Name", settings.resolved_name
  end

  def test_invalid_values_raise_with_all_problems
    settings.url = "cocina-tradicional.es"
    settings.port = 99_999
    settings.slow_ms = -1
    error = assert_raises(ArgumentError) { settings.to_h }
    assert_match(/url must start/, error.message)
    assert_match(/port must be/, error.message)
    assert_match(/slow_ms/, error.message)
  end
end
