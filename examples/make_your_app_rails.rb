# config/initializers/monitor_metrics.rb in make_your_app_rails (Mongoid 6, Rails 5.2)
MonitorMetrics.configure do |c|
  c.app do |a|
    a.id    = "makeyourapp"     # keep it stable: the collector keys history by it
    a.name  = "Make Your App"
    a.url   = "https://makeyourapp.es"
    a.order = 4
    # a.port   = 3000           # detected from Puma / `rails s -p` when omitted
    # a.screen = "session_name" # checked when set
  end

  c.metric :users, label: "Users" do
    User.count
  end

  # A backlog means generation is stuck: WARNING above 10, DOWN above 50.
  c.metric :generations_processing, label: "Generations in progress", overview: true,
                                    warn_above: 10, critical_above: 50 do
    Generation.where(state: :processing).count
  end

  c.metric :generations_per_day, label: "Generations per day", type: :series, ttl: 600 do
    times = Generation.where(:created_at.gte => 14.days.ago.beginning_of_day).pluck(:created_at)
    MonitorMetrics::Buckets.count(times, every: 1.day.to_i, last: 14)
  end

  c.metric :last_generations, label: "Last generations", type: :table do
    Generation.order_by(created_at: :desc).limit(5).map do |g|
      { "type" => g.type.to_s, "state" => g.state.to_s, "at" => g.created_at.strftime("%d/%m %H:%M") }
    end
  end
end
