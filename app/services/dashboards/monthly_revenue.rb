module Dashboards
  # Approved subscription revenue per calendar month (Cairo time), oldest first, with empty
  # months filled in as zero so the chart always has `months` columns. One GROUP BY; if the
  # subscriptions table ever outgrows that, cache the result or keep a monthly rollup.
  class MonthlyRevenue
    Month = Data.define(:date, :cents)

    def self.call(months: 7) = new(months).call

    def initialize(months)
      @months = months
    end

    def call
      first = (Time.zone.today.beginning_of_month - (@months - 1).months)
      totals = Subscription.active
                           .where(reviewed_at: first.in_time_zone..)
                           .group(Arel.sql(month_sql))
                           .sum(:amount_cents)
                           .transform_keys { |month| month.to_date }

      Array.new(@months) { |i| first + i.months }.map { |date| Month.new(date, totals.fetch(date, 0)) }
    end

    private

    # tzinfo name comes from the app's own config, never from input.
    def month_sql
      "date_trunc('month', timezone('#{Time.zone.tzinfo.name}', subscriptions.reviewed_at))"
    end
  end
end
