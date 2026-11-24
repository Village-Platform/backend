FactoryBot.define do
  factory :totp_credential do
    user
    otp_secret { ROTP::Base32.random }

    trait(:confirmed) { confirmed_at { Time.current } }
  end
end
