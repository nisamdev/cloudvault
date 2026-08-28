# frozen_string_literal: true

# Taking somebody out of a family, and settling what they leave behind.
#
# What they shared goes home with them. They uploaded it, it was theirs
# throughout, and being removed from a family does not make their photograph
# somebody else's — so it is unshared back to their own private files, whole
# and still theirs, and the family stops seeing it.
#
# This is the second answer to the question. The first was that the household
# kept what it had been given, which reads well until you watch it happen: the
# person who took the photograph loses it, and the person who removed them
# keeps it. Whatever the argument for a household keeping the passports
# somebody scanned for it, it cannot be worth taking their own pictures off
# them.
#
# So nothing changes hands. What leaves the family is only the sharing.
class FamilyDeparture
  Summary = Struct.new(:files, :records, :folders, :sealed_secrets, keyword_init: true) do
    def anything? = files.positive? || records.positive? || folders.positive?

    def to_h
      { files: files, records: records, folders: folders, sealed_secrets: sealed_secrets }
    end
  end

  # Shared with the family, as opposed to kept private within it.
  SHARED_FILE_VISIBILITIES = %w[family shared_link].freeze

  # Everything already handed over by the rule this one replaces.
  #
  # Files were transferred to the family owner when somebody was removed, which
  # is exactly the outcome that turned out to be wrong. The family grant records
  # who shared each one — `granted_by` is set to the sharer and never moves — so
  # the ones taken from people who are no longer in the family can be handed
  # back, and unshared, as they should have been at the time.
  #
  # Also repairs any file whose visibility column and access grant have drifted
  # apart: one saying "shared with the family" while granting nobody anything
  # is listed on every family screen and opens for none of them.
  #
  # @return [Hash] what it changed
  def self.settle_orphans
    given_back = 0

    Family.find_each do |family|
      member_ids = family.family_members.pluck(:user_id)

      AccessGrant.where(subject_type: "Family", subject_id: family.id).find_each do |grant|
        sharer_id = grant.granted_by_id
        next if sharer_id.blank? || member_ids.include?(sharer_id)

        resource = grant.resource
        next unless resource.is_a?(StoredFile) || resource.is_a?(VaultRecord)
        next unless User.exists?(id: sharer_id)

        send_home(resource, sharer_id)
        given_back += 1
      end

      # A folder left behind by somebody who has gone belongs to whoever is
      # still here to keep it tidy; it holds no content of its own.
      Folder.where(family_id: family.id).where.not(user_id: member_ids)
            .update_all(user_id: family.owner_id, updated_at: Time.current)
    end

    { given_back: given_back, regranted: resync_grants }
  end

  # Back to whoever shared it, and out of the family.
  def self.send_home(resource, owner_id)
    if resource.is_a?(StoredFile)
      family_id = resource.family_id
      size = resource.size.to_i
      resource.update_columns(user_id: owner_id, visibility: "private", family_id: nil,
                              updated_at: Time.current)
      AccessGrant.where(resource: resource, subject_type: "Family").destroy_all
      release_storage(family_id, size)
    else
      resource.update_columns(user_id: owner_id, visibility: "private", family_id: nil,
                              updated_at: Time.current)
    end
  end

  def self.release_storage(family_id, bytes)
    return if family_id.blank? || bytes.zero?

    Family.where(id: family_id)
          .update_all("family_storage_used = GREATEST(family_storage_used - #{bytes.to_i}, 0)")
  end

  # A file whose column says "shared with the family" and which grants nobody
  # anything appears in every family listing and opens for none of them.
  def self.resync_grants
    fixed = 0

    StoredFile.where.not(family_id: nil).where(visibility: SHARED_FILE_VISIBILITIES).find_each do |file|
      next if AccessGrant.exists?(resource: file, subject_type: "Family", subject_id: file.family_id)

      file.send(:sync_family_grant)
      fixed += 1
    end

    fixed
  end

  def initialize(membership)
    @membership = membership
    @family = membership.family
    @leaver = membership.user
    @heir_id = @family.owner_id
  end

  def call
    files = shared_files.to_a
    records = shared_records.to_a

    ActiveRecord::Base.transaction do
      files.each { |file| self.class.send_home(file, @leaver.id) }
      records.each { |record| self.class.send_home(record, @leaver.id) }
      # A folder is a place, not a possession: it stays with the family.
      shared_folders.update_all(user_id: @heir_id, updated_at: Time.current) if @heir_id.present?

      # Anything granted to them by name on this family's things goes too;
      # being removed should not leave a side door open.
      revoke_their_grants
      # And the app should stop showing them a family they are no longer in.
      look_elsewhere
      @membership.destroy!
    end

    Summary.new(files: files.size, records: records.size, folders: 0, sealed_secrets: 0)
  end

  private

  def shared_files
    StoredFile.where(user_id: @leaver.id, family_id: @family.id,
                     visibility: SHARED_FILE_VISIBILITIES)
  end

  def shared_records
    VaultRecord.where(user_id: @leaver.id, family_id: @family.id, visibility: "family")
  end

  def shared_folders
    Folder.where(user_id: @leaver.id, family_id: @family.id)
  end

  def revoke_their_grants
    AccessGrant.where(subject_type: "User", subject_id: @leaver.id).find_each do |grant|
      resource = grant.resource
      grant.destroy if resource.respond_to?(:family_id) && resource.family_id == @family.id
    end
  end

  def look_elsewhere
    return unless @leaver.current_family_id == @family.id

    other = @leaver.family_memberships.where.not(family_id: @family.id).first
    @leaver.update_columns(current_family_id: other&.family_id, updated_at: Time.current)
  end
end
