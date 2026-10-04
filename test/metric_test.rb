require "test_helper"

class MetricTest < Minitest::Test
  def build(type, ttl: 60, options: {}, &block)
    MonitorMetrics::Metric.new("k", "K", type, nil, ttl, block, options)
  end

  def test_caches_within_ttl
    calls = 0
    metric = build(:number) { calls += 1 }
    now = Time.now
    metric.evaluate(now)
    metric.evaluate(now + 30)
    assert_equal 1, calls
    assert_equal 2, metric.evaluate(now + 61)["value"]
  end

  def test_failure_keeps_last_good_value_as_stale
    fail_now = false
    metric = build(:number, ttl: 0) { fail_now ? raise("boom") : 7 }
    metric.evaluate
    fail_now = true
    result = metric.evaluate
    assert_equal 7, result["value"]
    assert result["stale"]
    assert_match(/boom/, result["error"])
  end

  def test_number_rejects_non_numeric
    result = build(:number) { "12" }.evaluate
    assert_nil result["value"]
    assert_match(/expected a number/, result["error"])
  end

  def test_series_accepts_hash_and_times
    t = Time.at(1_700_000_000)
    result = build(:series) { { t + 60 => 2, t => 1 } }.evaluate
    assert_equal [[1_700_000_000, 1.0], [1_700_000_060, 2.0]], result["value"]
  end

  def test_table_collects_columns_and_serializes_cells
    t = Time.utc(2026, 1, 2, 3, 4, 5)
    result = build(:table) { [{ name: "Paella", at: t }, { "name" => "Gazpacho", votes: 3 }] }.evaluate
    assert_equal %w[name at votes], result["value"]["columns"]
    assert_equal [["Paella", "2026-01-02T03:04:05Z", nil], ["Gazpacho", nil, 3]], result["value"]["rows"]
  end

  def test_unknown_type_raises
    assert_raises(ArgumentError) { build(:pie) { 1 } }
  end

  def test_levels_from_thresholds
    value = 0
    metric = build(:number, ttl: 0, options: { warn_above: 10, critical_above: 100 }) { value }
    assert_equal "ok", metric.evaluate["level"]
    value = 11
    assert_equal "warning", metric.evaluate["level"]
    value = 101
    result = metric.evaluate
    assert_equal "critical", result["level"]
    assert_equal({ "warn_above" => 10, "critical_above" => 100 }, result["thresholds"])
  end

  def test_below_thresholds
    metric = build(:number, options: { warn_below: 5, critical_below: 1 }) { 3 }
    assert_equal "warning", metric.evaluate["level"]
  end

  def test_no_thresholds_means_no_level
    result = build(:number, options: { overview: true }) { 3 }.evaluate
    assert_nil result["level"]
    assert_equal true, result["overview"]
    assert_equal false, result["hidden"]
  end

  def test_threshold_validation
    assert_raises(ArgumentError) { build(:series, options: { warn_above: 1 }) { [] } }
    assert_raises(ArgumentError) { build(:number, options: { warn_above: 10, critical_above: 5 }) { 1 } }
    assert_raises(ArgumentError) { build(:number, options: { warn_above: "10" }) { 1 } }
    assert_raises(ArgumentError) { build(:number, options: { colour: "red" }) { 1 } }
  end
end
