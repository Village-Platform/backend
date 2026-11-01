require "rails_helper"

RSpec.describe "Admin Full CRUD and Soft Deletion", type: :request do
  let!(:admin) { sign_in_admin }

  describe "Firms soft deletion and management" do
    it "soft-deletes, filters, restores, and permanently deletes a firm" do
      firm = create(:firm, name: "مخبز النور")

      # Soft delete
      delete "/admin/firms/#{firm.id}"
      expect(response).to redirect_to("/admin/firms")
      expect(firm.reload.deleted?).to be(true)

      # Disappears from default listing
      get "/admin/firms"
      expect(response.body).not_to include("مخبز النور")

      # Appears in deleted filter
      get "/admin/firms", params: { deleted: "only" }
      expect(response.body).to include("مخبز النور")
      expect(response.body).to include("محذوف")

      # Show page accessible for deleted record
      get "/admin/firms/#{firm.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("نشاط محذوف")
      expect(response.body).to include("استعادة النشاط")

      # Restore
      patch "/admin/firms/#{firm.id}/restore"
      expect(response).to redirect_to("/admin/firm/#{firm.id}").or redirect_to("/admin/firms/#{firm.id}")
      expect(firm.reload.deleted?).to be(false)

      # Soft delete again then destroy fully
      delete "/admin/firms/#{firm.id}"
      expect(firm.reload.deleted?).to be(true)

      delete "/admin/firms/#{firm.id}/destroy_fully"
      expect(response).to redirect_to("/admin/firms")
      expect(Firm.with_deleted.exists?(firm.id)).to be(false)
    end
  end

  describe "Users soft deletion and management" do
    it "soft-deletes, filters, restores, and permanently deletes a user" do
      user = create(:user, name: "أحمد علي", phone: "+201011112222")

      # Soft delete
      delete "/admin/users/#{user.id}"
      expect(response).to redirect_to("/admin/users")
      expect(user.reload.deleted?).to be(true)

      # Disappears from default listing
      get "/admin/users"
      expect(response.body).not_to include("أحمد علي")

      # Appears in deleted filter
      get "/admin/users", params: { deleted: "only" }
      expect(response.body).to include("أحمد علي")
      expect(response.body).to include("محذوف")

      # Show page accessible for deleted user
      get "/admin/users/#{user.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("حساب محذوف")
      expect(response.body).to include("استعادة الحساب")

      # Restore
      patch "/admin/users/#{user.id}/restore"
      expect(response).to redirect_to("/admin/users/#{user.id}")
      expect(user.reload.deleted?).to be(false)

      # Admin cannot delete their own account
      delete "/admin/users/#{admin.id}"
      expect(response).to redirect_to("/admin/users")
      expect(flash[:alert]).to include("لا يمكنك حذف حسابك الشخصي")
      expect(admin.reload.deleted?).to be(false)

      # Admin cannot permanently delete their own account
      delete "/admin/users/#{admin.id}/destroy_fully"
      expect(response).to redirect_to("/admin/users")
      expect(admin.reload.deleted?).to be(false)

      # Destroy fully other user
      delete "/admin/users/#{user.id}/destroy_fully"
      expect(response).to redirect_to("/admin/users")
      expect(User.with_deleted.exists?(user.id)).to be(false)
    end
  end

  describe "Articles soft deletion and management" do
    it "shows article, soft-deletes, restores, and permanently deletes" do
      article = create(:article, title: "افتتاح المركز الطبي", author: admin)

      # Show action
      get "/admin/articles/#{article.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("افتتاح المركز الطبي")

      # Soft delete
      delete "/admin/articles/#{article.id}"
      expect(response).to redirect_to("/admin/articles")
      expect(article.reload.deleted?).to be(true)

      # Disappears from default index
      get "/admin/articles"
      expect(response.body).not_to include("افتتاح المركز الطبي")

      # Appears in deleted filter
      get "/admin/articles", params: { deleted: "only" }
      expect(response.body).to include("افتتاح المركز الطبي")

      # Restore
      patch "/admin/articles/#{article.id}/restore"
      expect(response).to redirect_to("/admin/articles/#{article.id}")
      expect(article.reload.deleted?).to be(false)

      # Destroy fully
      delete "/admin/articles/#{article.id}/destroy_fully"
      expect(response).to redirect_to("/admin/articles")
      expect(Article.with_deleted.exists?(article.id)).to be(false)
    end
  end

  describe "Subscriptions full CRUD" do
    let!(:user) { create(:user) }
    let!(:plan) { create(:subscription_plan, price_cents: 20_000, duration_days: 30) }

    it "creates a manual subscription, edits it, and deletes it" do
      # New form
      get "/admin/subscriptions/new", params: { user_id: user.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("إضافة اشتراك جديد")

      # Create manual active subscription
      post "/admin/subscriptions", params: {
        subscription: {
          user_id: user.id,
          subscription_plan_id: plan.id,
          payment_method: "instapay",
          amount_cents: 20_000,
          status: "active",
          notes: "تم الدفع يدوياً نقداً"
        }
      }
      expect(response).to redirect_to(%r{/admin/subscriptions/\d+})
      subscription = Subscription.last
      expect(subscription.user).to eq(user)
      expect(subscription.active?).to be(true)
      expect(user.reload.firm_admin?).to be(true)

      # Edit form
      get "/admin/edit_subscription/#{subscription.id}" rescue nil
      get "/admin/subscriptions/#{subscription.id}/edit"
      expect(response).to have_http_status(:ok)

      # Update
      patch "/admin/subscriptions/#{subscription.id}", params: {
        subscription: { notes: "ملاحظة معدلة", amount_cents: 25_000 }
      }
      expect(response).to redirect_to("/admin/subscriptions/#{subscription.id}")
      expect(subscription.reload.notes).to eq("ملاحظة معدلة")
      expect(subscription.amount_cents).to eq(25_000)

      # Delete
      delete "/admin/subscriptions/#{subscription.id}"
      expect(response).to redirect_to("/admin/subscriptions")
      expect(Subscription.exists?(subscription.id)).to be(false)
    end

    it "filters subscriptions by plan and expiring status" do
      sub1 = create(:subscription, :current, user:, subscription_plan: plan)
      other_plan = create(:subscription_plan)
      sub2 = create(:subscription, :current, subscription_plan: other_plan)

      get "/admin/subscriptions", params: { subscription_plan_id: plan.id }
      expect(response.body).to include("##{sub1.id}")
      expect(response.body).not_to include("##{sub2.id}")
    end
  end

  describe "Categories and Plans details and toggles" do
    it "toggles category activation and shows category details" do
      category = create(:category, active: true)
      firm = create(:firm, category:)

      get "/admin/categories/#{category.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(category.name)
      expect(response.body).to include(firm.name)

      patch "/admin/categories/#{category.id}/toggle"
      expect(category.reload.active?).to be(false)
    end

    it "toggles plan activation and shows plan details" do
      plan = create(:subscription_plan, active: true)
      sub = create(:subscription, :current, subscription_plan: plan)

      get "/admin/subscription_plans/#{plan.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(plan.name)
      expect(response.body).to include(sub.user.name)

      patch "/admin/subscription_plans/#{plan.id}/toggle"
      expect(plan.reload.active?).to be(false)
    end
  end

  describe "Notifications management" do
    include ActiveJob::TestHelper

    it "lists, searches and shows a guest install's notification" do
      device = create(:device, installation_id: "guest-install-9")
      row = Notification.create!(device:, kind: :system_announcement, title: "إعلان للزوار", body: "نص")

      get "/admin/notifications", params: { q: "للزوار" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("guest-install-9")

      get "/admin/notifications/#{row.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("زائر")
    end

    it "views notifications, sends to a specific user, and deletes" do
      target_user = create(:user, name: "محمود حسن")

      # New form
      get "/admin/notifications/new"
      expect(response).to have_http_status(:ok)

      # Send to specific user
      post "/admin/notifications", params: {
        notification: {
          user_id: target_user.id,
          title: "تنبيه هام",
          body: "يرجى تحديث بيانات النشاط"
        }
      }
      expect(response).to redirect_to("/admin/notifications")
      notification = Notification.last
      expect(notification.user).to eq(target_user)
      expect(notification.title).to eq("تنبيه هام")

      # Index
      get "/admin/notifications"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("تنبيه هام")

      # Show
      get "/admin/notifications/#{notification.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("يرجى تحديث بيانات النشاط")

      # Delete
      delete "/admin/notifications/#{notification.id}"
      expect(response).to redirect_to("/admin/notifications")
      expect(Notification.exists?(notification.id)).to be(false)
    end

    it "broadcasts to all users through a campaign to the everyone topic" do
      create_list(:user, 3)

      perform_enqueued_jobs do
        post "/admin/notification_campaigns", params: {
          notification_campaign: { title: "إعلان عام", body: "أهلاً بأهل القرية جميعاً", screen: "none",
                                   topic_ids: [ Topic.everyone.id ] }
        }
      end

      expect(Notification.where(title: "إعلان عام").count).to eq(User.not_deleted.count)
      expect(Fcm.client.deliveries.sole[:topic]).to eq("all")
    end
  end
end
