module Admin
  class DashboardController < BaseController
    def show
      @stats = {
        pending_subscriptions: Subscription.pending.count,
        current_subscriptions: Subscription.current.count,
        expiring_soon: expiring.count,
        pending_firms: Firm.pending.count,
        firms: Firm.count,
        pending_articles: Article.pending.count,
        users: User.count,
        published_articles: Article.published.count,
        deleted_firms: Firm.only_deleted.count,
        deleted_users: User.only_deleted.count,
        deleted_articles: Article.only_deleted.count,
        total_deleted: Firm.only_deleted.count + User.only_deleted.count + Article.only_deleted.count
      }
      # Ordered so the view can take the maximum off the front instead of scanning.
      @firms_by_category = Firm.visible.joins(:category).group("categories.name").count.sort_by { |_, n| -n }
      @pending = Subscription.pending.includes(:user, :subscription_plan).order(:created_at).limit(10)
      @expiring = expiring.includes(:user, :subscription_plan).order(:ends_at).limit(10)
      @pending_firms = Firm.pending.includes(:category, :owner).order(:created_at).limit(10)
      @revenue = Dashboards::MonthlyRevenue.call(months: 7)
      @activity = Dashboards::RecentActivity.call(limit: 6)
    end

    private

    def expiring
      Subscription.current.where(ends_at: ..7.days.from_now)
    end
  end
end
