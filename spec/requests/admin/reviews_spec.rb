require "rails_helper"

RSpec.describe "Admin review queue", type: :request do
  it "lists pending firms and articles for a super admin" do
    sign_in_admin
    firm = create(:firm, :pending)
    article = create(:article, :pending)

    get "/admin/reviews"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(firm.name, article.title)
    expect(response.body).to include(approve_admin_firm_path(firm), approve_admin_article_path(article))
  end

  it "shows the empty states when nothing waits" do
    sign_in_admin
    get "/admin/reviews"
    expect(response.body).to include("لا توجد أنشطة بانتظار المراجعة", "لا توجد مقالات بانتظار المراجعة")
  end

  it "is open to reviewer admins" do
    sign_in_admin(create(:user, role: :admin))
    get "/admin/reviews"
    expect(response).to have_http_status(:ok)
  end

  it "redirects anonymous visitors to login" do
    get "/admin/reviews"
    expect(response).to redirect_to(admin_login_path)
  end
end
