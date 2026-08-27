# frozen_string_literal: true

# One letter a day at most, listing everything of theirs that is running out.
#
# Not one email per record. Five separate messages about five dates is how a
# useful reminder becomes a filter rule.
class ExpiryReminderMailer < ApplicationMailer
  def upcoming(user, dues, register_url)
    @user = user
    @dues = dues.sort_by(&:days)
    @register_url = register_url
    @soonest = @dues.first

    mail(to: user.email, subject: subject_for(@dues))
  end

  private

  # The subject line is the reminder. Somebody reading it on a lock screen
  # should learn the thing without opening anything.
  def subject_for(dues)
    first = dues.first
    lead = "#{first.record.title} — #{phrase(first.field.label)} #{when_phrase(first.days)}"

    return lead if dues.size == 1

    "#{lead}, and #{dues.size - 1} other#{dues.size == 2 ? "" : "s"}"
  end

  # Lowered so it reads as a sentence — unless it starts with an acronym, which
  # is how "MOT due" became "mot due".
  def phrase(label)
    label.match?(/\A[A-Z]{2,}/) ? label : label[0].downcase + label[1..].to_s
  end

  def when_phrase(days)
    return "today" if days.zero?
    return "in #{days} day#{days == 1 ? "" : "s"}" if days < 45

    months = (days / 30.44).round
    months < 12 ? "in #{months} month#{months == 1 ? "" : "s"}" : "in #{(months / 12.0).round} years"
  end
end
