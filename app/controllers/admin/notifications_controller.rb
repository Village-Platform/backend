module Admin
  class NotificationsController < BaseController
    before_action :set_notification, only: %i[show destroy]

    def index
      scope = Notification.includes(:user, :device).latest_first
      scope = scope.where(kind: params[:kind]) if Notification.kinds.key?(params[:kind])
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
      if params[:status] == "read"
        scope = scope.where.not(read_at: nil)
      elsif params[:status] == "unread"
        scope = scope.unread
      end
      if params[:q].present?
        scope = scope.left_joins(:user).where(
          "notifications.title ILIKE :q OR notifications.body ILIKE :q OR users.name ILIKE :q OR users.phone ILIKE :q",
          q: like(params[:q])
        )
      end

      @notifications, @meta = paginate(filter(scope))
    end

    def show; end

    def new
      @notification = Notification.new(kind: :system_announcement)
      @users = User.not_deleted.order(:name)
    end

    # One user: the inbox row and a push to each of their devices (Notifier). Everyone, or a group,
    # is a campaign to a topic instead (Admin::NotificationCampaignsController).
    def create
      attrs = params.require(:notification).permit(:user_id, :title, :body, :screen, :target_id)
      title = attrs[:title].to_s.strip
      body = attrs[:body].to_s.strip
      destination = Notifications::Destination.new(screen: attrs[:screen].presence || "none", id: attrs[:target_id])
      user = User.not_deleted.find_by(id: attrs[:user_id])

      error = if title.blank? || body.blank? then "يجب إدخال عنوان الإشعار ونصه."
      elsif user.nil? then "يجب اختيار المستخدم المستلم."
      elsif !Notifications::Destination::ADMIN_SCREENS.include?(destination.screen) || !destination.valid?
        destination.error || "الشاشة غير معروفة."
      end
      return render_new(attrs, error) if error

      Notifier.notify(user:, kind: :system_announcement, destination:, title:, body:)
      redirect_to admin_notifications_path, notice: "تم إرسال الإشعار للمستخدم #{user.name}."
    end

    def destroy
      destroy_and_redirect(@notification, admin_notifications_path)
    end

    private

    def render_new(attrs, error)
      flash.now[:alert] = error
      @notification = Notification.new(title: attrs[:title], body: attrs[:body], user_id: attrs[:user_id])
      @users = User.not_deleted.order(:name)
      render :new, status: :unprocessable_content
    end

    def set_notification
      @notification = Notification.find(params[:id])
    end
  end
end
