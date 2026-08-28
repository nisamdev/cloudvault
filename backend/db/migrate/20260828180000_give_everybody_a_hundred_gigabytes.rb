# frozen_string_literal: true

# 256 MB per person and 2 GB per household were the numbers of a demo. A
# household that actually keeps its photographs in here runs out in an
# afternoon.
class GiveEverybodyAHundredGigabytes < ActiveRecord::Migration[8.1]
  ONE_HUNDRED_GB = 107374182400

  def up
    change_column_default :users, :storage_quota, ONE_HUNDRED_GB
    change_column_default :families, :family_storage_quota, ONE_HUNDRED_GB
    # Everybody already here, too — a default only reaches the next account.
    User.update_all(storage_quota: ONE_HUNDRED_GB)
    Family.update_all(family_storage_quota: ONE_HUNDRED_GB)
  end

  def down
    change_column_default :users, :storage_quota, 268_435_456
    change_column_default :families, :family_storage_quota, 2_147_483_648
  end
end
