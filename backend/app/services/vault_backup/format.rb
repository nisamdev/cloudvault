# frozen_string_literal: true

module VaultBackup
  # On-disk layout for encrypted `.vault` backup files.
  module Format
    MAGIC = "CVBK"
    VERSION = 1
    INNER_MANIFEST = "manifest.json"
    DATABASE_DUMP = "database.dump"
    FILES_PREFIX = "files/"
  end
end
