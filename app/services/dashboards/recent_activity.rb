module Dashboards
  # A feed derived at read time from the newest rows of each source. It is not an event log:
  # it cannot say who did something. If audit becomes a requirement, write an events row from
  # Subscriptions::Approve / Firms::Review instead and read that.
  class RecentActivity
    Entry = Data.define(:icon, :text, :at, :path)

    def self.call(limit: 8) = new(limit).call

    def initialize(limit)
      @limit = limit
    end

    def call
      (subscription_entries + firm_entries + article_entries)
        .sort_by(&:at).reverse.first(@limit)
    end

    private

    def routes = Rails.application.routes.url_helpers

    def subscription_entries
      Subscription.active.where.not(reviewed_at: nil).includes(:user, :subscription_plan)
                  .order(reviewed_at: :desc).limit(@limit).map do |s|
        Entry.new(:subscriptions, "اعتماد اشتراك #{s.subscription_plan.name} — #{s.user.name}",
                  s.reviewed_at, routes.admin_subscription_path(s))
      end
    end

    def firm_entries
      Firm.includes(:category).order(created_at: :desc).limit(@limit).map do |f|
        verb = f.pending? ? "طلب نشاط جديد" : "نشاط جديد"
        Entry.new(:firms, "#{verb}: #{f.name}", f.created_at, routes.admin_firm_path(f))
      end
    end

    def article_entries
      Article.published.order(published_at: :desc).limit(@limit).map do |a|
        Entry.new(:articles, "نشر مقال: #{a.title}", a.published_at, routes.admin_article_path(a))
      end
    end
  end
end
