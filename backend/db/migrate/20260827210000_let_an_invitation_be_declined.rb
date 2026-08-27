# frozen_string_literal: true

# Saying no is not the same as the inviter changing their mind.
#
# Both take the invitation out of the pending list, but only one of them is
# worth showing the person who sent it: "they declined" is an answer, and
# "I cancelled it" is not.
class LetAnInvitationBeDeclined < ActiveRecord::Migration[8.1]
  def change
    add_column :family_invitations, :declined_at, :datetime

    # One pending invitation per person per family, and a declined one is not
    # pending. Without this, saying no once would mean never being asked again.
    remove_index :family_invitations, column: %i[family_id email],
                 name: "index_family_invitations_pending"
    add_index :family_invitations, %i[family_id email],
              unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL AND declined_at IS NULL",
              name: "index_family_invitations_pending"
  end
end
