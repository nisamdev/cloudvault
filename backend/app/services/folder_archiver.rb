# frozen_string_literal: true

# Collects everything inside a folder, recursively, as (path, file) pairs ready
# to be written into a ZIP.
#
# Only files the caller may actually see are included — a shared folder can hold
# other members' private uploads.
class FolderArchiver
  MAX_ENTRIES = 5_000

  Entry = Struct.new(:path, :stored_file, keyword_init: true)

  def initialize(folder:, user:)
    @folder = folder
    @user = user
  end

  # @return [Array<Entry>] relative path inside the archive -> file
  def entries
    @entries ||= collect(@folder, "").first(MAX_ENTRIES)
  end

  def empty_directories
    @empty_directories ||= begin
      with_files = entries.map { |e| File.dirname(e.path) }.to_set
      all_dirs.reject { |dir| with_files.any? { |d| d == dir.chomp("/") || d.start_with?(dir) } }
    end
  end

  def total_size
    entries.sum { |entry| entry.stored_file.size.to_i }
  end

  def filename
    "#{@folder.name.parameterize.presence || 'folder'}.zip"
  end

  private

  def collect(folder, prefix)
    here = "#{prefix}#{sanitize(folder.name)}/"

    files = StoredFile.active
                      .where(folder_id: folder.id)
                      .includes(:user, attachment_attachment: :blob)
                      .select { |file| PermissionChecker.can_view?(@user, file) }

    entries = files.map do |file|
      Entry.new(path: "#{here}#{unique_name(here, file)}", stored_file: file)
    end

    children = Folder.active.where(parent_id: folder.id).order(:name)
    entries + children.flat_map { |child| collect(child, here) }
  end

  # Two files can share a name in the same folder once one has been renamed, and
  # a ZIP with duplicate paths confuses some extractors.
  def unique_name(dir, file)
    @seen ||= Hash.new(0)
    name = sanitize(file.name)
    key = "#{dir}#{name.downcase}"

    @seen[key] += 1
    return name if @seen[key] == 1

    ext = File.extname(name)
    "#{File.basename(name, ext)} (#{@seen[key] - 1})#{ext}"
  end

  def all_dirs
    dirs = []
    walk = lambda do |folder, prefix|
      here = "#{prefix}#{sanitize(folder.name)}/"
      dirs << here
      Folder.active.where(parent_id: folder.id).order(:name).each { |child| walk.call(child, here) }
    end
    walk.call(@folder, "")
    dirs
  end

  # Strips path separators and parent-directory hops so a crafted name cannot
  # write outside the archive root when extracted (zip-slip). Upload names are
  # already basenamed, but renames accept anything.
  def sanitize(name)
    cleaned = name.to_s.tr("/\\", "_").gsub("..", "_").strip
    cleaned = "_#{cleaned}" if cleaned.start_with?(".")
    cleaned.presence || "untitled"
  end
end
