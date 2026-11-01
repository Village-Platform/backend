module Admin
  # Base for all dashboard pages: Arabic, cookie session. Super admins reach every page; admins
  # (reviewers) only the actions a controller opens to them with `allow_reviewers`.
  class BaseController < ActionController::Base
    include Pagination
    include Filterable

    layout "admin"

    class_attribute :reviewer_actions, instance_writer: false, default: [].freeze

    # Opens these actions to admins as well as super admins: the review queue.
    def self.allow_reviewers(*actions)
      self.reviewer_actions = (reviewer_actions + actions.map(&:to_s)).freeze
    end

    around_action :use_arabic
    before_action :require_admin
    before_action :require_super_admin

    helper_method :current_admin

    rescue_from ActiveRecord::RecordNotFound do
      redirect_to admin_root_path, alert: "العنصر غير موجود."
    end

    private

    # Admin filters get the admin allowlist tier.
    def filter_auth_object = current_admin

    def current_admin
      @current_admin ||= AdminSession.find_admin(session)
    end

    def require_admin
      return if current_admin

      reset_session
      redirect_to admin_login_path, alert: "يجب تسجيل الدخول أولاً."
    end

    # An admin landing anywhere else is sent to the firms waiting for review, which is always open
    # to them, so this never loops.
    def require_super_admin
      return if current_admin.super_admin? || reviewer_actions.include?(action_name)

      redirect_to admin_firms_path(status: "pending"), alert: "هذه الصفحة لمدير النظام فقط."
    end

    # Pagy keeps its own per-thread locale for the pager's labels; it is reset afterwards so a
    # Puma thread that next serves the API does not carry it over.
    def use_arabic(&action)
      Pagy::I18n.locale = "ar"
      I18n.with_locale(:ar, &action)
    ensure
      Pagy::I18n.locale = nil
    end

    # Escaped ILIKE pattern for simple search boxes.
    def like(term)
      "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s.strip)}%"
    end

    def destroy_and_redirect(record, path)
      if record.destroy
        redirect_to path, notice: "تم الحذف بنجاح."
      else
        redirect_to path, alert: record.errors.full_messages.to_sentence.presence || "لا يمكن حذف هذا العنصر."
      end
    end

    def restore_and_redirect(record, path)
      if record.recover
        redirect_to path, notice: "تمت استعادة السجل بنجاح."
      else
        redirect_to path, alert: record.errors.full_messages.to_sentence.presence || "فشلت عملية الاستعادة."
      end
    end

    def destroy_fully_and_redirect(record, path)
      if record.destroy_fully!
        redirect_to path, notice: "تم الحذف النهائي بنجاح."
      else
        redirect_to path, alert: "فشل الحذف النهائي."
      end
    end
  end
end
