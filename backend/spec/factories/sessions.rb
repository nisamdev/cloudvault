FactoryBot.define do
  factory :refresh_token do
    user
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0 Safari/537.36" }
    ip_address { "192.168.1.20" }
  end

  factory :file_version do
    stored_file
    created_by { stored_file.user }
    sequence(:version_number) { |n| n }
    size { 100 }
  end
end
