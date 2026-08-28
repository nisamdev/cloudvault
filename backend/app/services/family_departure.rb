# frozen_string_literal: true

# Taking somebody out of a family, and settling what they leave behind.
#
# A holiday photograph and a scanned deed are not the same kind of thing and do
# not want the same answer, so the family says which is which — see
# `Family#departure_policy`. By default a photograph goes home with whoever took
# it, and documents and register entries stay with the household they were
# contributed to.
#
# "home" unshares it back to their own files: still theirs, whole, nothing
# deleted, and the family stops seeing it. "stay" leaves it shared and passes it
# to whoever owns the family, so nobody outside still holds the keys to what the
# household depends on.
#
# One thing overrides the policy: a file attached to a record that stays, stays.
# A retained record pointing at a document that walked out of the door is worse
# than either answer.
class FamilyDeparture
  Summary = Struct.new(:went_home, :stayed, :policy, keyword_init: true) do
    def to_h = { went_home: went_home, stayed: stayed, policy: policy }
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
    policy = @family.departure_policy
    leaving, staying = split_files(policy)
    records = shared_records.to_a

    ActiveRecord::Base.transaction do
      leaving.each { |file| self.class.send_home(file, @leaver.id) }
      hand_over(StoredFile.where(id: staying.map(&:id)))

      if policy[:records] == "home"
        records.each { |record| self.class.send_home(record, @leaver.id) }
      else
        hand_over(VaultRecord.where(id: records.map(&:id)))
      end

      # A folder is a place, not a possession: it stays either way.
      hand_over(shared_folders)

      # Anything granted to them by name on this family's things goes too;
      # being removed should not leave a side door open.
      revoke_their_grants
      # And the app should stop showing them a family they are no longer in.
      look_elsewhere
      @membership.destroy!
    end

    Summary.new(
      went_home: leaving.size + (policy[:records] == "home" ? records.size : 0),
      stayed: staying.size + (policy[:records] == "stay" ? records.size : 0),
      policy: policy
    )
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

  # Which of their files go with them and which stay, by kind — and never a
  # document some retained record depends on.
  def split_files(policy)
    files = shared_files.to_a
    pinned = attached_to_retained_records(policy)

    files.partition do |file|
      kind = file.file_type == "image" ? :photos : :files
      policy[kind] == "home" && !pinned.include?(file.id)
    end
  end

  # A record that stays keeps the documents it points at, whatever the policy
  # says about documents.
  def attached_to_retained_records(policy)
    return Set.new if policy[:records] == "home"

    RecordAttachment.where(vault_record_id: shared_records.select(:id))
                    .pluck(:stored_file_id)
                    .to_set
  end

  def hand_over(scope)
    return 0 if @heir_id.blank? || @heir_id == @leaver.id

    scope.update_all(user_id: @heir_id, updated_at: Time.current)
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
