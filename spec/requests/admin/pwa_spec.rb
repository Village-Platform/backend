require "rails_helper"

RSpec.describe "Admin PWA", type: :request do
  it "serves a manifest scoped to the dashboard with icons that exist" do
    get "/manifest.json"

    expect(response).to have_http_status(:ok)
    expect(json).to include("start_url" => "/admin", "scope" => "/admin", "display" => "standalone", "dir" => "rtl")
    expect(json["icons"].map { it["sizes"] }).to include("192x192", "512x512")
    json["icons"].each do |icon|
      expect(Rails.public_path.join(icon["src"].delete_prefix("/"))).to exist, "missing #{icon["src"]}"
    end
  end

  it "serves a service worker whose precached offline page exists" do
    get "/service-worker.js"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
    expect(Rails.public_path.join("offline.html")).to exist
  end

  it "links the manifest and registers the worker from every admin page" do
    get "/admin/login"

    expect(response.body).to include('rel="manifest" href="/manifest.json"')
    expect(response.body).to include('register("/service-worker.js", { scope: "/admin" })')
  end
end
