# frozen_string_literal: true

# Writes encrypted secrets on a record and keeps the previous value when one
# changes.
class RecordSecretsSync
  class VaultLocked < StandardError; end

  def initialize(record, vault_key:)
    @record = record
    @vault_key = vault_key
  end

  # @param secrets [Hash, ActionController::Parameters, nil]
  def call(secrets)
    return if secrets.nil?

    hash = secrets.respond_to?(:to_unsafe_h) ? secrets.to_unsafe_h : secrets.to_h
    hash = hash.stringify_keys
    allowed = @record.template&.secret_fields&.map(&:key) || []
    keys = hash.keys & allowed
    return if keys.empty?

    needs_unlock = keys.any? { |key| hash[key].present? } ||
                   keys.any? { |key| hash[key].blank? && @record.record_secrets.exists?(key: key) }
    raise VaultLocked, "Unlock the private section before saving passwords." if needs_unlock && @vault_key.blank?

    keys.each { |key| apply!(key, hash[key]) }
  end

  private

  def apply!(key, value)
    existing = @record.record_secrets.find_by(key: key)

    if value.blank?
      existing&.destroy!
      return
    end

    sealed = RecordSecretSealer.seal(value, @vault_key)

    if existing
      existing.secret_versions.create!(
        sealed: existing.sealed,
        replaced_at: Time.current
      )
      existing.update!(sealed: sealed[:sealed], kdf: sealed[:kdf])
    else
      @record.record_secrets.create!(key: key, sealed: sealed[:sealed], kdf: sealed[:kdf])
    end
  end
end
