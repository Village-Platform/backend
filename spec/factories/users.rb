FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:phone) { |n| format("010%08d", n) }
    password { "password123" }
    role { :user }

    trait(:firm_admin)  { role { :firm_admin } }
    trait(:admin)       { role { :admin } }
    trait(:super_admin) { role { :super_admin } }

    # Firm admin with a current (approved, not expired) subscription.
    trait :subscribed do
      role { :firm_admin }
      after(:create) { |user| create(:subscription, :current, user:) }
    end
  end
end
