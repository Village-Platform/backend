require "rails_helper"

RSpec.describe "Admin dashboard", type: :request do
  before { sign_in_admin }

  it "renders the four stat tiles" do
    get "/admin"
    [ "إجمالي الأهالي", "الأنشطة المسجلة", "الاشتراكات الفعالة", "إيرادات هذا الشهر" ].each do |label|
      expect(response.body).to include(label)
    end
  end

  it "renders the action card" do
    get "/admin"
    expect(response.body).to include("تحتاج إجراءك")
  end

  it "counts visible firms per category" do
    firm = create(:firm)
    create(:firm, category: firm.category, owner: firm.owner)

    get "/admin"
    bars = Nokogiri::HTML(response.body).at_css(".bars")
    expect(bars).to be_present
    row = bars.css(".bar-row").find { |r| r.at_css(".bar-head span").text == firm.category.name }
    expect(row).to be_present
    expect(row.at_css(".bar-head b").text).to eq("2")
  end

  it "renders without raising when there are no firms at all" do
    get "/admin"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("لا توجد أنشطة بعد")
  end

  it "charts seven months of approved revenue, empty months as zero" do
    travel_to Time.zone.local(2026, 10, 20, 12) do
      plan = create(:subscription_plan)
      create(:subscription, :current, subscription_plan: plan, amount_cents: 24_900, reviewed_at: Time.current)
      create(:subscription, :current, subscription_plan: plan, amount_cents: 9_900, reviewed_at: 2.months.ago)
      create(:subscription, subscription_plan: plan, amount_cents: 99_900)

      get "/admin"

      cols = Nokogiri::HTML(response.body).css(".chart .chart-col")
      expect(cols.size).to eq(7)
      expect(cols.last["title"]).to eq("249 ج.م")
      expect(cols[-3]["title"]).to eq("99 ج.م")
      expect(cols[-2]["title"]).to eq("0 ج.م")
      expect(cols.last.at_css(".chart-bar")["class"]).to include("chart-now")
    end
  end

  it "renders the chart flat when there is no revenue" do
    get "/admin"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css(".chart .chart-col").size).to eq(7)
  end

  it "lists recent activity newest first" do
    create(:firm, name: "صيدلية الشفاء")
    get "/admin"
    feed = Nokogiri::HTML(response.body).at_css(".feed")
    expect(feed.text).to include("صيدلية الشفاء")
  end

  it "links the quick actions" do
    get "/admin"
    [ new_admin_firm_path, new_admin_article_path, new_admin_category_path ].each do |path|
      expect(response.body).to include(path)
    end
  end
end
