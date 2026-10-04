# monitor_metrics

Private `/internal/metrics` JSON endpoint for Rails apps, read by the
[wall monitor](https://github.com/jmjurado23/server_monitor_metrics) collector that runs on the
same server.

Works with Rails 5.2 → 8.x, Ruby 2.7 → 4.x, ActiveRecord or Mongoid.

## Install

```ruby
# Gemfile
gem "monitor_metrics", git: "https://github.com/jmjurado23/monitor_metrics", tag: "v0.3.0"
```

The Railtie inserts the middleware at the top of the stack. Nothing else is needed for
the base report: app/Ruby/Rails versions, process uptime and memory, git revision, and
a ping of every database the app uses (ActiveRecord and/or Mongoid).

## Put the app on the wall

The app describes itself; nothing has to be added on the server or the Pi.

```ruby
# config/initializers/monitor_metrics.rb
MonitorMetrics.configure do |c|
  c.app do |a|
    a.id          = "cocina"                        # default: Rails module name, underscored
    a.name        = "Cocina Tradicional"            # default: Rails module name
    a.url         = "https://cocina-tradicional.es" # checked publicly through nginx
    a.hosts       = ["cocina.example"]              # extra hosts (url host and www. implied)
    a.port        = 3002                            # default: detected, see below
    a.socket      = "/tmp/cooking.socket"           # default: detected, see below
    a.screen      = "cooking_rails"                 # screen session to check
    a.health_path = "/"
    a.order       = 1                               # position on the wall
    a.slow_ms     = 1500                            # WARNING above this response time
    a.enabled     = true                            # false takes it off the wall
  end
end
```

When the app boots **as a server in production**, it writes
`~/.wallmon/apps.d/<id>.json` (folder 0700, file 0600, no secrets). The collector scans
that folder, so the app appears on the wall after its first restart, and stays there as
DOWN if it later crashes. Consoles, `rake` and `rails runner` never register.

- Address detection: `a.port` / `a.socket` win. Otherwise the app reads the sockets it
  **really** listens on from Linux `/proc` (TCP ports and Unix sockets like
  `unix:///tmp/app.socket`, Puma control sockets excluded). At boot Puma has not bound
  yet, so the entry is rewritten in the background as soon as it has. Without `/proc`,
  it falls back to the `puma` CLI binds, `-p`/`--port`, then `ENV["PORT"]`. `rails server`
  options are never used: they say 3000 even when Puma binds a socket. The report and
  the registry file say which source was used (`port_source`) and list every listener.
- `c.registry_dir` (or `MONITOR_METRICS_REGISTRY`) changes the folder;
  `c.register_environments` (default `%w[production]`) the environments;
  `MONITOR_METRICS_REGISTER=1` / `=0` forces it on or off.
- Set `a.id` explicitly: the default comes from the Rails module name, which may not
  match the product (make_your_app_rails is `MediaRails`), and the collector keys the
  traffic history by id.

## Declare your own metrics

```ruby
# config/initializers/monitor_metrics.rb
MonitorMetrics.configure do |c|
  c.app_name = "Cocina Tradicional"

  c.metric :recipes, label: "Recipes", overview: true do  # type: :number (default)
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

Display and alarm options (any metric type unless noted):

| option | effect |
|---|---|
| `overview: true` | shown on the app's tile on the overview screen |
| `hidden: true` | collected and sent, not shown |
| `warn_above:` / `warn_below:` | numbers only: the metric gets `level: "warning"` and the app turns WARNING |
| `critical_above:` / `critical_below:` | numbers only: `level: "critical"`, the app turns DOWN with the metric as reason |

```ruby
c.metric :failed_imports, label: "Failed imports", warn_above: 0, critical_above: 10 do
  Import.failed.where(:created_at.gte => 1.day.ago).count
end
```

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
