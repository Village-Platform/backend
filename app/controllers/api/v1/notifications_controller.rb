module Api
  module V1
    # Notifications are always scoped to the caller's inbox, so no Pundit policy is needed.
    #
    # Signed in: the user's inbox. A guest token plus an X-Installation-Id header: that install's
    # inbox, which only ever holds campaigns. The installation id is not a secret, so anyone who
    # knows it can read and mark those broadcasts; acceptable while nothing private reaches a guest
    # inbox, and the reason nothing should.
    class NotificationsController < BaseController
      INSTALLATION_HEADER = "X-Installation-Id".freeze

      before_action :set_inbox

      # GET /api/v1/notifications?unread=true
      def index
        scope = @inbox.latest_first
        scope = scope.unread if params[:unread].present?

        records, meta = paginate(filter(scope))
        meta[:unread_count] = @inbox.unread.count
        render_collection(records, meta, NotificationSerializer)
      end

      # PATCH /api/v1/notifications/:id/read
      def read
        notification = @inbox.find(params[:id])
        notification.mark_as_read!
        render_record(notification, NotificationSerializer)
      end

      # PATCH /api/v1/notifications/read_all
      def read_all
        now = Time.current
        @inbox.unread.update_all(read_at: now, updated_at: now)
        head :no_content
      end

      private

      def set_inbox
        @inbox = current_user&.notifications || guest_inbox
        render_error(:unauthorized, "unauthorized") unless @inbox
      end

      # An install the server has not seen yet (no FCM token so far) has an empty inbox. A signed-in
      # install answers 403: its guest rows are hidden until logout, like any other ownership rule.
      def guest_inbox
        installation_id = request.headers[INSTALLATION_HEADER].presence
        return unless guest_token? && installation_id

        device = Device.find_by(installation_id:)
        return Notification.none unless device
        raise Devices::OwnershipError if device.user_id

        device.notifications
      end
    end
  end
end
