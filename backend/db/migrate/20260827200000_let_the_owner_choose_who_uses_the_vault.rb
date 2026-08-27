# frozen_string_literal: true

# Who in the family may reach the family's own things.
#
# Role already says what somebody may *do* with a shared file — upload it,
# rename it, delete it. This says whether the shared half of the vault is open
# to them at all, which is a different question and one a household answers
# person by person: the teenager trusted with the wifi password but not with
# the mortgage.
#
# Nullable, and no default, on purpose. NULL means "whatever the role implies"
# — grown-ups in, onlookers out — so an existing family keeps behaving as it
# did and a new role brings its own sensible answer. Only an owner who has
# actually decided writes true or false into it.
#
# None of this touches anybody's private section. That is theirs alone: a
# passphrase nobody else holds is arithmetic, not policy.
class LetTheOwnerChooseWhoUsesTheVault < ActiveRecord::Migration[8.1]
  def change
    add_column :family_members, :can_use_vault, :boolean
    # Why it was turned off, so the owner remembers their own decision.
    add_column :family_members, :vault_note, :string
  end
end
