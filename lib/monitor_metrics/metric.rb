module MonitorMetrics
  # One declared metric plus its cached last result.
  class Metric
    TYPES = %w[number series table text].freeze
    MAX_SERIES_POINTS = 500
    MAX_TABLE_ROWS = 50
    MAX_TEXT = 500

    attr_reader :key, :label, :type, :unit, :ttl

    def initialize(key, label, type, unit, ttl, block)
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
        "computed_at" => @computed_at && @computed_at.utc.iso8601
      }
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
