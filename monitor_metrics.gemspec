require_relative "lib/monitor_metrics/version"

Gem::Specification.new do |spec|
  spec.name = "monitor_metrics"
  spec.version = MonitorMetrics::VERSION
  spec.authors = ["jmjurado23"]
  spec.summary = "Private /internal/metrics JSON endpoint for the wall monitor"
  spec.description = "Rack middleware + Railtie exposing app health, database pings and " \
                     "app-defined business metrics to the server-side wall monitor collector."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", ">= 2.0"

  spec.add_development_dependency "minitest", ">= 5.0"
  spec.add_development_dependency "rack-test", ">= 1.0"
end
