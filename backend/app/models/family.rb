# frozen_string_literal: true

class Family < ApplicationRecord
  belongs_to :owner, class_name: "User"

  has_many :family_members, dependent: :destroy
  has_many :users, through: :family_members
  has_many :family_invitations, dependent: :destroy
  has_many :access_grants, as: :subject, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }, allow_blank: true
  validates :family_storage_quota, :family_storage_used,
            numericality: { greater_than_or_equal_to: 0 }

  # The owner is always a member; creating one without the other would leave a
  # family nobody can administer.
  after_create :add_owner_as_member

  # What each kind of thing does when somebody leaves. A photograph is personal
  # and goes back to whoever took it; a document or a register entry was
  # contributed to the household and stays with it.
  DEPARTURE_CHOICES = %w[home stay].freeze
  DEPARTURE_KINDS = %i[photos files records].freeze

  validates :on_departure_photos, :on_departure_files, :on_departure_records,
            inclusion: { in: DEPARTURE_CHOICES }

  # @param kind [:photos, :files, :records]
  def keeps_on_departure?(kind)
    public_send("on_departure_#{kind}") == "stay"
  end

  def departure_policy
    DEPARTURE_KINDS.index_with { |kind| public_send("on_departure_#{kind}") }
  end

  def storage_remaining
    [ family_storage_quota - family_storage_used, 0 ].max
  end

  def storage_percent_used
    return 0 if family_storage_quota.zero?

    ((family_storage_used.to_f / family_storage_quota) * 100).round(1)
  end

  def member_for(user)
    return nil if user.nil?

    family_members.find_by(user_id: user.id)
  end

  private

  def add_owner_as_member
    family_members.create!(user: owner, role: "owner", joined_at: Time.current)
  end
end
