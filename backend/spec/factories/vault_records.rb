FactoryBot.define do
  factory :vault_record do
    association :user
    record_type { "service_account" }
    sequence(:title) { |n| "British Gas #{n}" }
    visibility { "private" }
    locked { false }
    data { { "provider" => "British Gas", "account_email" => "home@example.com" } }

    trait :family do
      visibility { "family" }
      association :family
    end

    trait :locked do
      locked { true }
    end

    trait :immigration do
      record_type { "immigration" }
      title { "Skilled Worker visa" }
      data do
        {
          "document_kind" => "Visa",
          "country" => "UK",
          "document_number" => "GB-123456",
          "expires_on" => "2027-06-01"
        }
      end
    end
  end
end
