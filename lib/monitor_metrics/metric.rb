module MonitorMetrics
  # One declared metric plus its cached last result.
  class Metric
    TYPES = %w[number series table text].freeze
    THRESHOLDS = %w[warn_above critical_above warn_below critical_below].freeze
    MAX_SERIES_POINTS = 500
    MAX_TABLE_ROWS = 50
    MAX_TEXT = 500

    attr_reader :key, :label, :type, :unit, :ttl, :overview, :hidden, :thresholds

    # options: overview: true  -> shown on the app's overview tile
    #          hidden: true    -> collected but not shown
    #          warn_above: / critical_above: / warn_below: / critical_below: (numbers only)
    #            -> the metric gets a level and can turn the app WARNING or DOWN
    def initialize(key, label, type, unit, ttl, block, options = {})
      @key = key
      @label = label.to_s
      @type = type.to_s
      raise ArgumentError, "unknown metric type #{type.inspect} (use #{TYPES.join(', ')})" unless TYPES.include?(@type)

      @unit = unit && unit.to_s
      @ttl = ttl.to_f
      @block = block
      @mutex = Mutex.new
      @value = nil
      @error = nil
      @computed_at = nil
      @duration_ms = nil
      @stale = false
      @overview = options[:overview] ? true : false
      @hidden = options[:hidden] ? true : false
      @thresholds = build_thresholds(options)
    end

    # "ok" / "warning" / "critical" against the thresholds, nil when the metric
    # has none or no numeric value.
    def level_for(value)
      return nil if @thresholds.empty? || !value.is_a?(Numeric)
      return "critical" if beyond?(value, "critical")
      return "warning" if beyond?(value, "warn")

      "ok"
    end

    # Returns the cached value, recomputing it when older than ttl. A failing
    # block keeps the last good value (flagged stale) so the wall screen does not
    # blank out on one bad query.
    def evaluate(now = Time.now)
      @mutex.synchronize do
        refresh(now) if @computed_at.nil? || (now - @computed_at) >= @ttl
        to_h
      end
    end

    private

    def refresh(now)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        @value = normalize(@block.call)
        @error = nil
        @stale = false
      rescue StandardError => e
        @error = "#{e.class}: #{e.message}"[0, 300]
        @stale = !@value.nil?
      end
      @duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      @computed_at = now
    end

    def to_h
      {
        "key" => key,
        "label" => label,
        "type" => type,
        "unit" => unit,
        "value" => @value,
        "error" => @error,
        "stale" => @stale ? true : false,
        "ms" => @duration_ms,
        "computed_at" => @computed_at && @computed_at.utc.iso8601,
        "overview" => overview,
        "hidden" => hidden,
        "thresholds" => @thresholds.empty? ? nil : @thresholds,
        "level" => level_for(@value)
      }
    end

    def build_thresholds(options)
      unknown = options.keys.map(&:to_s) - THRESHOLDS - %w[overview hidden]
      raise ArgumentError, "metric #{key}: unknown option(s) #{unknown.join(', ')}" unless unknown.empty?

      thresholds = {}
      THRESHOLDS.each do |name|
        value = options[name.to_sym]
        next if value.nil?
        raise ArgumentError, "metric #{key}: #{name} must be a number" unless value.is_a?(Numeric)

        thresholds[name] = value
      end
      if !thresholds.empty? && type != "number"
        raise ArgumentError, "metric #{key}: thresholds only apply to type: :number"
      end
      check_order(thresholds, "warn_above", "critical_above") { |w, c| w <= c }
      check_order(thresholds, "warn_below", "critical_below") { |w, c| w >= c }
      thresholds
    end

    def check_order(thresholds, warn, critical)
      return unless thresholds[warn] && thresholds[critical]
      return if yield(thresholds[warn], thresholds[critical])

      raise ArgumentError, "metric #{key}: #{warn} must be less severe than #{critical}"
    end

    def beyond?(value, prefix)
      above = @thresholds["#{prefix}_above"]
      below = @thresholds["#{prefix}_below"]
      (above && value > above) || (below && value < below) ? true : false
    end

    def normalize(raw)
      case type
      when "number" then normalize_number(raw)
      when "series" then normalize_series(raw)
      when "table" then normalize_table(raw)
      else raw.nil? ? nil : raw.to_s[0, MAX_TEXT]
      end
    end

    def normalize_number(raw)
      return nil if raw.nil?
      raise TypeError, "expected a number, got #{raw.class}" unless raw.is_a?(Numeric)

      raw.is_a?(Integer) ? raw : raw.to_f.round(4)
    end

    def normalize_series(raw)
      pairs = raw.is_a?(Hash) ? raw.to_a : Array(raw)
      points = pairs.map do |pair|
        raise TypeError, "series points must be [time, value] pairs" unless pair.is_a?(Array) && pair.size == 2

        [Buckets.to_epoch(pair[0]), pair[1].nil? ? nil : pair[1].to_f]
      end
      points.sort_by(&:first).last(MAX_SERIES_POINTS)
    end

    def normalize_table(raw)
      rows = Array(raw).first(MAX_TABLE_ROWS)
      columns = []
      rows.each do |row|
        raise TypeError, "table rows must be hashes" unless row.is_a?(Hash)

        row.each_key { |k| columns << k.to_s unless columns.include?(k.to_s) }
      end
      {
        "columns" => columns,
        "rows" => rows.map { |row| columns.map { |c| cell(row.key?(c) ? row[c] : row[c.to_sym]) } }
      }
    end

    def cell(value)
      case value
      when nil, true, false, Integer, String then value
      when Numeric then value.to_f.round(4)
      when Time then value.utc.iso8601
      else value.to_s
      end
    end
  end
end
