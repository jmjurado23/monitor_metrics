require "test_helper"

class BucketsTest < Minitest::Test
  def test_hourly_counts_end_with_current_bucket
    now = Time.utc(2026, 10, 3, 12, 30)
    times = [Time.utc(2026, 10, 3, 12, 5), Time.utc(2026, 10, 3, 12, 59),
             Time.utc(2026, 10, 3, 11, 0), Time.utc(2026, 10, 3, 9, 59), nil]
    series = MonitorMetrics::Buckets.count(times, every: 3600, last: 3, now: now)
    assert_equal [Time.utc(2026, 10, 3, 10).to_i, Time.utc(2026, 10, 3, 11).to_i, Time.utc(2026, 10, 3, 12).to_i],
                 series.map(&:first)
    assert_equal [0, 1, 2], series.map(&:last)
  end

  def test_daily_buckets_align_to_local_midnight
    now = Time.new(2026, 10, 3, 0, 30, 0, "+02:00")
    late_yesterday = Time.new(2026, 10, 2, 23, 50, 0, "+02:00")
    series = MonitorMetrics::Buckets.count([late_yesterday, now], every: 86_400, last: 2, now: now)
    assert_equal Time.new(2026, 10, 3, 0, 0, 0, "+02:00").to_i, series.last.first
    assert_equal [1, 1], series.map(&:last)
  end
end
