FactoryBot.define do
  factory :family do
    name { "The Smiths" }
    description { "Our family vault" }
    association :owner, factory: :user
  end

  factory :family_member do
    association :family
    association :user
    role { "viewer" }
    joined_at { Time.current }
  end

  factory :family_invitation do
    association :family
    association :invited_by, factory: :user
    sequence(:email) { |n| "invitee#{n}@smith.com" }
    role { "editor" }
  end
end
