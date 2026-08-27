# frozen_string_literal: true

# Photographs a phone left behind that nobody came back for.
#
# A record scan holds its pages as unattached blobs while the computer trims
# them. Most get used within minutes and the rest are abandoned — a link left
# open, a phone put down. Nothing else in the app creates unattached blobs, so
# anything still loose after a day was never claimed.
class PurgeHeldScansJob < ApplicationJob
  queue_as :maintenance

  KEEP_FOR = 1.day

  def perform
    stale = ActiveStorage::Blob.unattached.where(created_at: ...KEEP_FOR.ago)
    count = stale.count

    stale.find_each(&:purge_later)
    Rails.logger.info("[scan] released #{count} unclaimed page(s)") if count.positive?
    count
  end
end
