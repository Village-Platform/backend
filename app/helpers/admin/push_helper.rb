module Admin
  # The dashboard's web push button (admin_push.js). Hidden until the script finds the browser able
  # and not yet asked: a permission prompt must follow a click, or browsers block it for good.
  module PushHelper
    FIREBASE_ENV = {
      apiKey: "FIREBASE_WEB_API_KEY",
      projectId: "FIREBASE_PROJECT_ID",
      messagingSenderId: "FIREBASE_MESSAGING_SENDER_ID",
      appId: "FIREBASE_WEB_APP_ID",
      vapidKey: "FIREBASE_VAPID_KEY"
    }.freeze

    def push_toggle
      config = web_push_config or return

      tag.button(type: "button", class: "btn btn-ghost btn-sm", hidden: true,
                 data: { push_toggle: true, push_config: config.to_json, push_url: admin_push_device_path }) do
        safe_join([ icon(:bell, size: 16), "تفعيل الإشعارات" ])
      end
    end

    # Firebase's web config. Public values (every browser receives them), read from ENV so each
    # environment points at its own project. Nil until all are set, which hides the button: web
    # push fails closed, like a missing FCM_SERVICE_ACCOUNT_JSON.
    def web_push_config
      config = FIREBASE_ENV.transform_values { |name| ENV[name].presence }
      config if config.values.all?
    end
  end
end
