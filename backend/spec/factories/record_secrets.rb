FactoryBot.define do
  factory :record_secret do
    association :vault_record
    key { "password" }
    sealed { VaultCipher.seal(vault_key, "hunter2") }
    kdf { { "v" => 1, "scheme" => "vault_key" } }

    transient do
      vault_key { VaultCipher.random_key }
      plaintext { "hunter2" }
    end

    after(:build) do |secret, evaluator|
      secret.sealed = VaultCipher.seal(evaluator.vault_key, evaluator.plaintext)
    end

    trait :with_history do
      after(:create) do |secret, evaluator|
        secret.secret_versions.create!(
          sealed: VaultCipher.seal(evaluator.vault_key, "old-password"),
          replaced_at: 1.day.ago
        )
      end
    end
  end
end
