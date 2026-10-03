# monitor_metrics

Private `/internal/metrics` JSON endpoint for Rails apps, read by the
[wall monitor](https://github.com/jmjurado23/server_monitor_metrics) collector that runs on the
same server.

Works with Rails 5.2 → 8.x, Ruby 2.7 → 4.x, ActiveRecord or Mongoid.

## Install

```ruby
# Gemfile
gem "monitor_metrics", git: "https://github.com/jmjurado23/monitor_metrics", tag: "v0.1.0"
```

The Railtie inserts the middleware at the top of the stack. Nothing else is needed for
the base report: app/Ruby/Rails versions, process uptime and memory, git revision, and
a ping of every database the app uses (ActiveRecord and/or Mongoid).

## Declare your own metrics

```ruby
# config/initializers/monitor_metrics.rb
MonitorMetrics.configure do |c|
  c.app_name = "Cocina Tradicional"

  c.metric :recipes, label: "Recipes" do              # type: :number (default)
    Recipe.count
  end

  c.metric :signups, label: "Sign-ups per day", type: :series, ttl: 600 do
    times = User.where(:created_at.gte => 14.days.ago).pluck(:created_at)
    MonitorMetrics::Buckets.count(times, every: 1.day.to_i, last: 14)
  end

  c.metric :top, label: "Most voted", type: :table do  # array of hashes
    [{ "recipe" => "Paella", "votes" => 41 }]
  end

  c.metric :last_import, label: "Last import", type: :text do
    "today 06:00"
  end
end
```

| type | block returns | shown as |
|---|---|---|
| `:number` | a Numeric | big number |
| `:series` | `[[time, value], ...]` or `{ time => value }` | column or line chart |
| `:table` | `[{ "col" => value }, ...]` (max 50 rows) | table |
| `:text` | anything with `to_s` | text |

- Each block runs at most once per `ttl` seconds (default 60), so a heavy query does not
  run on every collector call.
- A block that raises does not break the endpoint: that metric reports the error and
  keeps showing its last good value, marked `stale`.
- `MonitorMetrics::Buckets.count` turns timestamps into evenly spaced buckets aligned to
  local time. The same code works on ActiveRecord and Mongoid.

Ready-made initializers for the four apps on the server are in [`examples/`](examples).

## Security

The endpoint answers **404** unless all of the following hold:

1. A token is configured: `config.token`, or `ENV["MONITOR_METRICS_TOKEN"]`, or the file
   `ENV["MONITOR_METRICS_TOKEN_FILE"]` / `~/.monitor_metrics_token` (the default, shared
   with the collector, so no app needs a new env var).
2. The request carries the token in `X-Monitor-Token` or `Authorization: Bearer`.
3. It comes from `127.0.0.1` / `::1` (`config.allowed_ips`).
4. It has **no** `X-Forwarded-For` / `X-Real-IP` / `Forwarded` header. nginx forwards
   public traffic from 127.0.0.1, so the address check alone is not enough
   (`config.reject_proxied`).

Also add `location ^~ /internal/ { return 404; }` to each site in nginx.

## Develop

```sh
bundle install
bundle exec rake test
```
