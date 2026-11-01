module Api
  module V1
    class AppConfigController < BaseController
      # Read before the app holds any token, and the one place an old app can learn it must update.
      skip_before_action :require_api_token!

      # GET /api/v1/app_config -> { data: { features: { plans: false } } }
      # Public and the same for every caller. Cached for 5 minutes, so a toggle reaches the apps
      # within that time without a request per screen.
      def show
        expires_in 5.minutes, public: true
        render json: { data: { features: FeatureFlag.to_h } }
      end
    end
  end
end
