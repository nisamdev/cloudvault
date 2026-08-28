# frozen_string_literal: true

# Off by default: a video is a different animal from a photo — a single Insta360
# clip can be gigabytes, and that should be an opt-in, not something that
# silently starts eating quota the first time somebody drags one in.
class AddVideosEnabledToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :videos_enabled, :boolean, null: false, default: false
  end
end
