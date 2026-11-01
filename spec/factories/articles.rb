FactoryBot.define do
  factory :article do
    association :author, factory: %i[user super_admin]
    sequence(:title) { |n| "Article #{n}" }
    body { "Body" }
    kind { :news }
    published_at { 1.hour.ago }

    trait(:draft) { published_at { nil } }
    trait(:pending) { review_status { :pending } }
    trait(:rejected) { review_status { :rejected }; rejection_reason { "Incomplete" } }
  end
end
