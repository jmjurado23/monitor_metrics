module MonitorMetrics
  # Database-agnostic helpers to turn timestamps into chart series, so the same
  # initializer code works on ActiveRecord and Mongoid:
  #
  #   times = Recipe.where(:created_at.gte => 7.days.ago).pluck(:created_at)
  #   MonitorMetrics::Buckets.count(times, every: 86_400, last: 7)
  module Buckets
    module_function

    # Counts timestamps into `last` consecutive buckets of `every` seconds ending
    # with the bucket that contains `now`. Buckets align to local time (so daily
    # buckets start at local midnight). Returns [[bucket_start_epoch, count], ...].
    def count(times, every: 3600, last: 24, now: Time.now)
      step = every.to_i
      raise ArgumentError, "every must be positive" unless step > 0

      offset = now.utc_offset
      current = align(now.to_i, step, offset)
      first = current - step * (last - 1)
      counts = Hash.new(0)
      times.each do |t|
        next if t.nil?

        bucket = align(to_epoch(t), step, offset)
        counts[bucket] += 1 if bucket >= first && bucket <= current
      end
      Array.new(last) { |i| [first + i * step, counts[first + i * step]] }
    end

    def align(epoch, step, offset)
      ((epoch + offset) / step) * step - offset
    end

    def to_epoch(value)
      case value
      when Integer then value
      when Numeric then value.to_i
      when Time then value.to_i
      when String then Time.parse(value).to_i
      else
        return value.to_time.to_i if value.respond_to?(:to_time)

        raise TypeError, "cannot use #{value.class} as a time"
      end
    end
  end
end
