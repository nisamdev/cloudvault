FactoryBot.define do
  factory :stored_file do
    association :user
    sequence(:name) { |n| "Document_#{n}.pdf" }
    mime_type { "application/pdf" }
    size { 1024 }
    file_type { "file" }
    visibility { "private" }

    trait :image do
      sequence(:name) { |n| "Photo_#{n}.png" }
      mime_type { "image/png" }
      file_type { "image" }
    end

    trait :trashed do
      trashed_at { Time.current }
    end

    # Attaches real bytes; only needed by specs that download or process.
    trait :with_attachment do
      after(:create) do |file|
        file.attachment.attach(
          io: StringIO.new("test file contents"),
          filename: file.name,
          content_type: file.mime_type
        )
      end
    end
  end

  factory :folder do
    association :user
    sequence(:name) { |n| "Folder #{n}" }
  end
end
