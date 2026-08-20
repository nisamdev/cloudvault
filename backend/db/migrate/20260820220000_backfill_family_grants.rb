class BackfillFamilyGrants < ActiveRecord::Migration[8.1]
  # Files shared with a family used to say so in a `visibility` column that
  # PermissionChecker read directly. Grants now answer that question, so every
  # family-visible file gets the grant it always implied.
  #
  # The role is "editor" because that is what family visibility meant: members
  # could change what was there. What an individual member can actually do is
  # still capped by their role in the family, which PermissionChecker applies.
  def up
    say_with_time "granting family access to family-visible files" do
      count = 0

      StoredFile.where(visibility: %w[family shared_link]).where.not(family_id: nil).find_each do |file|
        next if AccessGrant.exists?(resource: file, subject_type: "Family", subject_id: file.family_id)

        AccessGrant.create!(
          resource: file,
          subject_type: "Family",
          subject_id: file.family_id,
          role: "editor",
          granted_by_id: file.user_id
        )
        count += 1
      end

      count
    end
  end

  def down
    AccessGrant.where(subject_type: "Family").delete_all
  end
end
