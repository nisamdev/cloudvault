# frozen_string_literal: true

# The nightly look at what is running out.
#
# One letter per person at most, and a note of everything sent so tomorrow's run
# does not say it all again.
class SendExpiryRemindersJob < ApplicationJob
  queue_as :maintenance

  def perform
    sent = 0

    UpcomingExpiries.recipients.find_each do |user|
      dues = UpcomingExpiries.to_send(user)
      next if dues.empty?

      ExpiryReminderMailer.upcoming(user, dues, register_url).deliver_now
      dues.each { |due| ExpiryReminder.note!(user: user, due: due) }
      sent += 1
    rescue StandardError => e
      # One address that bounces must not stop the rest of the household
      # hearing about their passports.
      Rails.logger.error("[reminders] #{user.id}: #{e.class}: #{e.message}")
    end

    Rails.logger.info("[reminders] wrote to #{sent} person(s)")
    sent
  end

  private

  def register_url
    "#{Rails.configuration.x.app_url.to_s.chomp("/")}/household"
  end
end
