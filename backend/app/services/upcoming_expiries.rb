# frozen_string_literal: true

# Everything with a date running out, and who ought to hear about it.
#
# One place answers both questions the register asks: what should the screen
# show as coming up, and what should be written about tonight. Keeping them
# together is what stops the email disagreeing with the page.
class UpcomingExpiries
  Due = Struct.new(:record, :field, :date, :days, :threshold, keyword_init: true) do
    def expired? = days.negative?

    def to_h
      {
        record_id: record.id,
        title: record.title,
        record_type: record.record_type,
        field_key: field.key,
        label: field.label,
        date: date.iso8601,
        days: days
      }
    end
  end

  # What the register shows under "coming up". Wider than the mail schedule,
  # because a page can afford to mention something the post should not.
  SHOWN_WITHIN_DAYS = 120
  # Something that ran out is still worth showing for a while — it is usually
  # the most urgent thing on the page.
  SHOWN_EXPIRED_FOR_DAYS = 60

  class << self
    # Dates on one person's records, soonest first, for the screen.
    def for_user(user, within: SHOWN_WITHIN_DAYS)
      records = VaultRecord.active
                           .where(id: readable_record_ids(user))
                           .includes(:user)

      collect(records) do |due|
        due.days <= within && due.days >= -SHOWN_EXPIRED_FOR_DAYS
      end
    end

    # Dates that have crossed a step of their schedule today, for the post.
    #
    # A step counts as crossed when the days remaining have fallen to it or
    # past it — so a job that did not run for a week still writes rather than
    # skipping the date silently.
    def due_for_reminder(records = VaultRecord.active)
      collect(records, reminding_only: true) do |due|
        due.threshold = crossed_threshold(due)
        due.threshold.present?
      end
    end

    private

    # Which step of the schedule this date has reached, if any.
    def crossed_threshold(due)
      schedule = due.field.remind.to_a.sort.reverse
      # Nothing is written about a date that has already gone: the last
      # reminder before it was the last useful one.
      return nil if due.days.negative?

      schedule.find { |days| due.days <= days }
    end

    def collect(records, reminding_only: false)
      found = []

      records.find_each do |record|
        template = record.template
        next if template.nil?

        fields = reminding_only ? template.reminding_fields : template.expiry_fields

        fields.each do |field|
          date = parse(record.data[field.key])
          next if date.nil?

          due = Due.new(
            record: record, field: field, date: date,
            days: (date - Date.current).to_i
          )
          found << due if yield(due)
        end
      end

      found.sort_by(&:days)
    end

    def parse(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    # Records this person can actually see: their own, plus whatever their
    # families share.
    def readable_record_ids(user)
      family_ids = FamilyMember.where(user_id: user.id).pluck(:family_id)

      VaultRecord.where(user_id: user.id)
                 .or(VaultRecord.where(visibility: "family", family_id: family_ids))
                 .select(:id)
    end
  end
end
