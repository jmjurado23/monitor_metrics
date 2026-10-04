# config/initializers/monitor_metrics.rb in optimal_path/backend (PostgreSQL, Rails 7.0)
MonitorMetrics.configure do |c|
  c.app do |a|
    a.id    = "agroroute"     # keep it stable: the collector keys history by it
    a.name  = "AgroRoute"
    a.url   = "https://agroroute.es"
    a.order = 2
    # a.port   = 3000           # detected from Puma / `rails s -p` when omitted
    # a.screen = "session_name" # checked when set
  end

  # Paths are soft-deleted (deleted_at) and have no created_at: use computed_at.
  c.metric :paths_today, label: "Routes computed today", overview: true do
    Path.alive.where("computed_at >= ?", Time.zone.now.beginning_of_day).count
  end

  c.metric :users, label: "Users" do
    User.count
  end

  c.metric :vehicles, label: "Vehicles" do
    Vehicle.alive.count
  end

  c.metric :paths_per_day, label: "Routes per day", type: :series, ttl: 600 do
    times = Path.alive.where("computed_at >= ?", 14.days.ago.beginning_of_day).pluck(:computed_at)
    MonitorMetrics::Buckets.count(times, every: 1.day.to_i, last: 14)
  end

  c.metric :fuel_saved_today, label: "Fuel saved today", unit: "L" do
    Path.alive.where("computed_at >= ?", Time.zone.now.beginning_of_day).sum(:fuel_saved_l).round(1)
  end
end
