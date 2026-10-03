# config/initializers/monitor_metrics.rb in iloveradio (PostgreSQL, Rails 7.0)
MonitorMetrics.configure do |c|
  c.app_name = "I Love Radio"

  c.metric :played_today, label: "Songs played today" do
    PlayedSong.where("datetime >= ?", Time.zone.now.beginning_of_day).count
  end

  c.metric :stations, label: "Stations" do
    Station.count
  end

  # Let Postgres do the bucketing when the table is big.
  c.metric :played_per_hour, label: "Songs played per hour", type: :series, ttl: 300 do
    PlayedSong.where("datetime >= ?", 24.hours.ago)
              .group(Arel.sql("date_trunc('hour', datetime)"))
              .count
              .map { |hour, n| [hour, n] }
  end

  c.metric :top_songs, label: "Most played today", type: :table, ttl: 300 do
    PlayedSong.joins(:song)
              .where("played_songs.datetime >= ?", Time.zone.now.beginning_of_day)
              .group("songs.title").order(Arel.sql("count(*) DESC")).limit(5).count
              .map { |title, n| { "song" => title, "plays" => n } }
  end
end
