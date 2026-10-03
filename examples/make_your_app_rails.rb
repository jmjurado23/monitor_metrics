# config/initializers/monitor_metrics.rb in make_your_app_rails (Mongoid 6, Rails 5.2)
MonitorMetrics.configure do |c|
  c.app_name = "Make Your App"

  c.metric :users, label: "Users" do
    User.count
  end

  c.metric :generations_processing, label: "Generations in progress" do
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
