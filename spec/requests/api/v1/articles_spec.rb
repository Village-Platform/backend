require "rails_helper"

RSpec.describe "Articles API", type: :request do
  let(:super_admin) { create(:user, :super_admin) }

  it "lists only published articles, newest first" do
    create(:article, title: "Old", published_at: 2.days.ago)
    create(:article, title: "New", published_at: 1.hour.ago)
    create(:article, :draft, title: "Draft")
    create(:article, title: "Scheduled", published_at: 1.day.from_now)

    get "/api/v1/articles"

    expect(json["data"].map { _1["title"] }).to eq(%w[New Old])
  end

  it "filters by kind" do
    create(:article, kind: :news)
    create(:article, kind: :announcement, title: "Notice")

    get "/api/v1/articles", params: { kind: "announcement" }

    expect(json["data"].map { _1["title"] }).to eq([ "Notice" ])
  end

  it "lets super admins publish" do
    post "/api/v1/articles",
         params: { article: { title: "خبر", body: "...", published_at: Time.current } },
         headers: auth_headers(super_admin), as: :json

    expect(response).to have_http_status(:created)
    expect(json.dig("data", "author", "id")).to eq(super_admin.id)
  end

  it "submits an unsubscribed firm admin's article for review" do
    post "/api/v1/articles", params: { article: { title: "x", body: "y" } },
                             headers: auth_headers(create(:user, :firm_admin)), as: :json

    expect(response).to have_http_status(:created)
    expect(json.dig("data", "review_status")).to eq("pending")
  end
end
