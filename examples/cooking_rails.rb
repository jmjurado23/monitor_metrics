# config/initializers/monitor_metrics.rb in cooking_rails (Mongoid 6, Rails 5.2)
MonitorMetrics.configure do |c|
  c.app do |a|
    a.id    = "cocina"     # keep it stable: the collector keys history by it
    a.name  = "Cocina Tradicional"
    a.url   = "https://cocina-tradicional.es"
    a.order = 1
    # a.port   = 3000           # detected from Puma / `rails s -p` when omitted
    # a.screen = "session_name" # checked when set
  end

  c.metric :recipes, label: "Recipes", overview: true do
    Recipe.count
  end

  c.metric :signups_today, label: "Sign-ups today", overview: true do
    User.where(:created_at.gte => Time.zone.now.beginning_of_day).count
  end

  c.metric :signups_per_day, label: "Sign-ups per day", type: :series, ttl: 600 do
    times = User.where(:created_at.gte => 14.days.ago.beginning_of_day).pluck(:created_at)
    MonitorMetrics::Buckets.count(times, every: 1.day.to_i, last: 14)
  end

  c.metric :comments_per_hour, label: "Comments per hour", type: :series, ttl: 300 do
    times = Comment.where(:created_at.gte => 24.hours.ago).pluck(:created_at)
    MonitorMetrics::Buckets.count(times, every: 1.hour.to_i, last: 24)
  end
end
