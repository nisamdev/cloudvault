# frozen_string_literal: true

# Flattens a list of files into ZIP entries, with unique names so two
# "IMG_0001.jpg"s from different folders do not collide.
class FilesArchiver
  MAX_ENTRIES = 5_000

  Entry = Struct.new(:path, :stored_file, keyword_init: true)

  def initialize(files:, user:)
    @files = files
    @user = user
  end

  def entries
    @entries ||= begin
      list = []
      @files.each do |file|
        next unless PermissionChecker.can_view?(@user, file)
        next if file.locked? || file.encrypted?
        next unless file.attachment.attached?

        list << Entry.new(path: unique_name(file), stored_file: file)
        break if list.size >= MAX_ENTRIES
      end
      list
    end
  end

  def total_size
    entries.sum { |entry| entry.stored_file.size.to_i }
  end

  def filename
    stamp = Time.current.strftime("%Y-%m-%d")
    "cloudvault-#{stamp}.zip"
  end

  private

  def unique_name(file)
    @seen ||= Hash.new(0)
    name = sanitize(file.name)
    key = name.downcase

    @seen[key] += 1
    return name if @seen[key] == 1

    ext = File.extname(name)
    "#{File.basename(name, ext)} (#{@seen[key] - 1})#{ext}"
  end

  def sanitize(name)
    cleaned = name.to_s.tr("/\\", "_").gsub("..", "_").strip
    cleaned = "_#{cleaned}" if cleaned.start_with?(".")
    cleaned.presence || "untitled"
  end
end
