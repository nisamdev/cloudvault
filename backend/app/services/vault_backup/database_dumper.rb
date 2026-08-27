# frozen_string_literal: true

module VaultBackup
  # Full Postgres dump — structure and data, including binary secret columns.
  class DatabaseDumper
    class Error < StandardError; end

    def initialize(output_path:)
      @output_path = output_path
    end

    def call
      url = database_url
      raise Error, "DATABASE_URL is not set." if url.blank?

      FileUtils.mkdir_p(File.dirname(@output_path))

      success = system("pg_dump", "-Fc", "--no-owner", "--no-acl", "-f", @output_path, url, exception: false)
      raise Error, "pg_dump failed (is it installed and is the database reachable?)." unless success
      raise Error, "pg_dump produced no output." unless File.size?(@output_path)

      @output_path
    end

    private

    def database_url
      ENV["DATABASE_URL"].presence || build_url_from_config
    end

    def build_url_from_config
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      return nil if config[:database].blank?

      user = config[:username] || ENV.fetch("POSTGRES_USER", "postgres")
      password = config[:password] || ENV["POSTGRES_PASSWORD"]
      host = config[:host] || "localhost"
      port = config[:port] || 5432
      db = config[:database]

      auth = password.present? ? "#{user}:#{password}" : user
      "postgres://#{auth}@#{host}:#{port}/#{db}"
    end
  end
end
