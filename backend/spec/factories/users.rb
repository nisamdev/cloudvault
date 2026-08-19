FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "member#{n}@smith.com" }
    password { "password123" }
    full_name { "Family Member" }

    trait :oauth do
      password { nil }
      oauth_provider { "google" }
      sequence(:oauth_id) { |n| "google-uid-#{n}" }
    end
  end
end
