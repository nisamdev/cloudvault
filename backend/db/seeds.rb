# frozen_string_literal: true

# Development seed data: the Smith family from the UI prototype.
#
# Idempotent — safe to run repeatedly. Refuses to run in production.

if Rails.env.production?
  puts "Refusing to seed in production."
  exit
end

PASSWORD = "password123"

dad = User.find_or_initialize_by(email: "dad@smith.com")
dad.assign_attributes(
  full_name: "Dad Smith",
  password: PASSWORD,
  timezone: "Europe/London",
  storage_quota: ENV.fetch("USER_STORAGE_QUOTA_BYTES", 268_435_456).to_i
)
dad.save!

mum = User.find_or_initialize_by(email: "mum@smith.com")
mum.assign_attributes(full_name: "Mum Smith", password: PASSWORD, timezone: "Europe/London")
mum.save!

teen = User.find_or_initialize_by(email: "teen@smith.com")
teen.assign_attributes(full_name: "Teen Smith", password: PASSWORD, timezone: "Europe/London")
teen.save!

family = Family.find_or_initialize_by(owner: dad)
family.assign_attributes(
  name: "The Smith Family",
  description: "Documents and photos we all share",
  family_storage_quota: ENV.fetch("FAMILY_STORAGE_QUOTA_BYTES", 2_147_483_648).to_i
)
family.save!

# The owner's membership is created by Family's after_create hook.
family.family_members.find_or_create_by!(user: mum) do |member|
  member.role = "editor"
  member.joined_at = Time.current
end

family.family_members.find_or_create_by!(user: teen) do |member|
  member.role = "viewer"
  member.joined_at = Time.current
end

# A pending invitation so the acceptance flow has something to exercise.
unless family.family_invitations.pending.exists?(email: "gran@smith.com")
  invitation = family.family_invitations.create!(
    email: "gran@smith.com",
    role: "viewer",
    invited_by: dad
  )
  puts "  pending invite token (dev only): #{invitation.raw_token}"
end

puts <<~SUMMARY

  Seeded #{User.count} users and #{Family.count} family.

    dad@smith.com  / #{PASSWORD}  (owner)
    mum@smith.com  / #{PASSWORD}  (editor)
    teen@smith.com / #{PASSWORD}  (viewer)

SUMMARY
