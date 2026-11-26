# Endpoints called by the k8s CronJob (see deploy/k8s/cron.yaml).
# It sends "Authorization: Bearer <CRON_SECRET>"; anything else gets 401.
module Internal
  class CronController < ActionController::API
    before_action :authenticate_cron!

    # GET /internal/cron/subscription_reminders  (daily)
    def subscription_reminders
      sent = SubscriptionExpiryRemindersJob.perform_now
      render json: { sent: }
    end

    private

    def authenticate_cron!
      secret = ENV["CRON_SECRET"].to_s
      given = request.authorization.to_s
      return if secret.present? && ActiveSupport::SecurityUtils.secure_compare(given, "Bearer #{secret}")

      head :unauthorized
    end
  end
end
