FactoryBot.define do
  factory :firm do
    category
    association :owner, factory: %i[user subscribed]
    sequence(:name) { |n| "Firm #{n}" }
    phone { "01012345678" }
    status { :active }

    trait(:pending) { status { :pending } }
    trait(:rejected) { status { :suspended }; rejection_reason { "Incomplete" } }
  end
end
