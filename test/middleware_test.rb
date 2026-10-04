require "test_helper"

class MiddlewareTest < Minitest::Test
  include Rack::Test::Methods

  TOKEN = "s3cret-token".freeze
  DOWNSTREAM = ->(_env) { [200, { "content-type" => "text/plain" }, ["app"]] }

  def setup
    MonitorMetrics.reset!
    MonitorMetrics.configure do |c|
      c.token = TOKEN
      c.app_name = "TestApp"
      c.check_databases = false
    end
  end

  def app
    MonitorMetrics::Middleware.new(DOWNSTREAM)
  end

  def get_metrics(headers = {}, ip = "127.0.0.1")
    get "/internal/metrics", {}, { "REMOTE_ADDR" => ip }.merge(headers)
  end

  def test_other_paths_pass_through
    get "/recipes"
    assert_equal 200, last_response.status
    assert_equal "app", last_response.body
  end

  def test_valid_token_from_localhost_returns_report
    get_metrics("HTTP_X_MONITOR_TOKEN" => TOKEN)
    assert_equal 200, last_response.status
    assert_equal "application/json", last_response.headers["content-type"]
    body = JSON.parse(last_response.body)
    assert_equal 2, body["schema"]
    assert_equal "TestApp", body["app"]["name"]
    assert_equal "testapp", body["monitor"]["id"]
    assert_equal "/internal/metrics", body["monitor"]["metrics_path"]
    assert_equal RUBY_VERSION, body["app"]["ruby"]
    assert_equal [], body["metrics"]
  end

  def test_bearer_token_is_accepted
    get_metrics("HTTP_AUTHORIZATION" => "Bearer #{TOKEN}")
    assert_equal 200, last_response.status
  end

  def test_wrong_or_missing_token_is_404
    get_metrics("HTTP_X_MONITOR_TOKEN" => "nope")
    assert_equal 404, last_response.status
    get_metrics
    assert_equal 404, last_response.status
  end

  def test_remote_address_is_404
    get_metrics({ "HTTP_X_MONITOR_TOKEN" => TOKEN }, "203.0.113.9")
    assert_equal 404, last_response.status
  end

  # nginx forwards public requests from 127.0.0.1; proxy headers give them away.
  def test_request_through_proxy_is_404_even_with_token
    get_metrics("HTTP_X_MONITOR_TOKEN" => TOKEN, "HTTP_X_FORWARDED_FOR" => "203.0.113.9")
    assert_equal 404, last_response.status
    get_metrics("HTTP_X_MONITOR_TOKEN" => TOKEN, "HTTP_X_REAL_IP" => "203.0.113.9")
    assert_equal 404, last_response.status
  end

  def test_no_token_configured_disables_endpoint
    MonitorMetrics.config.token = nil
    with_env("MONITOR_METRICS_TOKEN" => nil, "MONITOR_METRICS_TOKEN_FILE" => "/nonexistent") do
      get_metrics("HTTP_X_MONITOR_TOKEN" => "")
      assert_equal 404, last_response.status
    end
  end

  def test_token_from_file
    MonitorMetrics.config.token = nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "token")
      File.write(path, "from-file\n")
      with_env("MONITOR_METRICS_TOKEN" => nil, "MONITOR_METRICS_TOKEN_FILE" => path) do
        get_metrics("HTTP_X_MONITOR_TOKEN" => "from-file")
        assert_equal 200, last_response.status
      end
    end
  end

  def test_post_is_404
    post "/internal/metrics", {}, "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_MONITOR_TOKEN" => TOKEN
    assert_equal 404, last_response.status
  end

  def test_metrics_are_reported_and_failures_isolated
    MonitorMetrics.configure do |c|
      c.metric(:recipes, label: "Recipes") { 42 }
      c.metric(:broken) { raise "db down" }
    end
    get_metrics("HTTP_X_MONITOR_TOKEN" => TOKEN)
    assert_equal 200, last_response.status
    metrics = JSON.parse(last_response.body)["metrics"]
    assert_equal 42, metrics[0]["value"]
    assert_nil metrics[0]["error"]
    assert_equal "Broken", metrics[1]["label"]
    assert_match(/db down/, metrics[1]["error"])
  end

  private

  def with_env(vars)
    saved = vars.keys.map { |k| [k, ENV[k]] }.to_h
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

require "tmpdir"
