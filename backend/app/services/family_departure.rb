# frozen_string_literal: true

# Taking somebody out of a family, and settling what they leave behind.
#
# What they shared, they shared with the household: the passport they scanned,
# the deed they photographed, the folder of school letters. Removing a person
# must not take those with them — but it must stop being theirs, or somebody
# outside the family still holds the keys to what the family depends on. Left
# as the owner, they could go on renaming it, unsharing it, sharing it back,
# and deleting it, from outside the family that relies on it.
#
# So the shared half passes to whoever owns the family, and their private half
# stays untouched and entirely theirs. Nothing is deleted either way.
class FamilyDeparture
  Summary = Struct.new(:files, :records, :folders, :sealed_secrets, keyword_init: true) do
    def anything? = files.positive? || records.positive? || folders.positive?

    def to_h
      { files: files, records: records, folders: folders, sealed_secrets: sealed_secrets }
    end
  end

  # Shared with the family, as opposed to kept private within it.
  SHARED_FILE_VISIBILITIES = %w[family shared_link].freeze

  def initialize(membership)
    @membership = membership
    @family = membership.family
    @leaver = membership.user
    @heir_id = @family.owner_id
  end

  def call
    # Counted before anything moves: once it has changed hands it no longer
    # matches "what they shared".
    record_ids = shared_records.pluck(:id)
    sealed = RecordSecret.where(vault_record_id: record_ids).count

    summary = nil

    ActiveRecord::Base.transaction do
      summary = Summary.new(
        files: hand_over(shared_files),
        records: hand_over(shared_records),
        folders: hand_over(shared_folders),
        sealed_secrets: sealed
      )

      # Anything granted to them by name on this family's things goes with
      # them; being removed should not leave a side door open.
      revoke_their_grants
      # And the app should stop showing them a family they are no longer in.
      look_elsewhere
      @membership.destroy!
    end

    summary
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

  # The heir is the family's owner, who is by definition still in it.
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
