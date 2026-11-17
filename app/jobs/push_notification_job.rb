# Pushes one inbox notification to one device. One job per device, so a retry never re-sends to the
# user's other phones. Skips a device that has changed hands since the notification was created.
class PushNotificationJob < ApplicationJob
  include FcmRetries

  queue_as :default

  def perform(notification_id, device_id)
    notification = Notification.find_by(id: notification_id)
    device = Device.find_by(id: device_id)
    return unless notification && device && device.user_id == notification.user_id

    Fcm.client.send_to_token(device.token, payload_for(notification, device))
    record_push("ok")
  rescue Fcm::Unregistered
    device.destroy
    Observability::Metrics.increment(:push_tokens_pruned)
    record_push("unregistered")
  rescue Fcm::InvalidArgument => e
    Rails.logger.error("[PushNotificationJob] FCM refused notification_id=#{notification_id}: #{e.message}")
    record_push("invalid")
  end

  private

  # The app routes a tap by screen + id; a dashboard browser gets the page to open as well.
  def payload_for(notification, device)
    data = notification.data.merge("notification_id" => notification.id)
    data["admin_path"] = admin_path_for(notification) if device.web?
    Fcm::Message.payload(title: notification.title, body: notification.body, data:)
  end

  def admin_path_for(notification)
    Notifications::Destination.new(screen: notification.data["screen"] || "none", id: notification.data["id"]).admin_path
  end

  def push_source = "system"
end
