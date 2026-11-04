require "rails_helper"

RSpec.describe "Admin shell", type: :request do
  before { sign_in_admin }

  it "renders the grouped sidebar with the design's vocabulary" do
    get "/admin"
    [ "عام", "المحتوى", "الأشخاص", "المالية", "المراجعة", "طلبات المراجعة", "التصنيفات", "الأنشطة", "الباقات والأسعار" ].each do |label|
      expect(response.body).to include(label)
    end
  end

  it "renders the topbar chrome" do
    get "/admin"
    # Assert the control, not its wording: the placeholder has already changed once, when
    # the firms-scoped box became a global search.
    search = Nokogiri::HTML(response.body).at_css(".topbar [data-admin-search]")
    expect(search).to be_present
    expect(search["placeholder"]).to be_present
    expect(response.body).to include(admin_logout_path)
  end

  it "renders both brand marks in the sidebar so one shows per theme" do
    get "/admin"
    mark = Nokogiri::HTML(response.body).at_css(".sidebar .brand-mark")
    expect(mark).to be_present
    expect(mark.css("img").map { |img| img["src"] })
      .to contain_exactly("/brand/web/mark.png", "/brand/web/mark-light.png")
  end

  it "renders a theme toggle" do
    get "/admin"
    expect(response.body).to include(admin_theme_path)
  end

  it "shows a theme-aware mark in empty states" do
    get "/admin/users", params: { q: "nothing-matches-this" }
    mark = Nokogiri::HTML(response.body).at_css(".empty .brand-mark")
    expect(mark).to be_present
    expect(mark.css("img").map { |img| img["src"] })
      .to contain_exactly("/brand/web/mark.png", "/brand/web/mark-light.png")
  end
end
