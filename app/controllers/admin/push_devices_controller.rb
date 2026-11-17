module Admin
  # Registers this browser for web push. The browser becomes a Device (platform "web") of the
  # signed-in admin, so the existing Notifier → PushNotificationJob path delivers to it: the admin
  # gets the same pushes as their inbox, e.g. a submission waiting for review.
  class PushDevicesController < BaseController
    allow_reviewers :create

    # POST /admin/push_device  { installation_id, token }
    def create
      device = Devices::Register.call(
        installation_id: params.require(:installation_id),
        token: params.require(:token),
        user: current_admin,
        platform: "web",
        locale: "ar"
      )
      # Logout removes the row (SessionsController#destroy), so the next person at a shared
      # computer does not receive this admin's pushes.
      session[:push_installation_id] = device.installation_id
      head :no_content
    rescue Devices::OwnershipError
      head :forbidden
    rescue ActiveRecord::RecordInvalid
      head :unprocessable_content
    end
  end
end
