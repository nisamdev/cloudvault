# frozen_string_literal: true

# What has been shared with this user, expanded into plain id lists a query can
# use.
#
# A grant on a folder reaches everything inside it, which is convenient to write
# and awkward to ask a database about — so the tree is walked once here and the
# result cached for the request. Family vaults hold tens of folders, not
# millions, so this stays cheaper than a recursive query.
class GrantedResources
  def initialize(user)
    @user = user
  end

  def empty?
    grants.empty?
  end

  def file_ids
    @file_ids ||= grants.select { |g| g.resource_type == "StoredFile" }.map(&:resource_id)
  end

  # The granted folders plus every folder beneath them.
  def folder_ids
    @folder_ids ||= begin
      roots = grants.select { |g| g.resource_type == "Folder" }.map(&:resource_id)
      Folder.where(id: roots).flat_map { |folder| [ folder.id ] + folder.descendant_ids }.uniq
    end
  end

  private

  def grants
    @grants ||= @user ? AccessGrant.for_subjects(@user).to_a : []
  end
end
