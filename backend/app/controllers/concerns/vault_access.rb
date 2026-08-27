# frozen_string_literal: true

# Reading the private section's unlock token off a request.
#
# The token arrives in a header rather than a cookie on purpose: it must not be
# sent automatically by the browser, because "unlocked" should mean "this tab,
# now", not "this machine, since Tuesday".
module VaultAccess
  extend ActiveSupport::Concern

  HEADER = "X-Vault-Key"

  included do
    helper_method :vault_unlocked? if respond_to?(:helper_method)
  end

  # @return [String, nil] the vault key, when this request carries a live token
  def vault_key
    return @vault_key if defined?(@vault_key)

    token = request.headers[HEADER].presence
    @vault_key = token && VaultSession.vault_key(token, current_user)
  end

  def vault_unlocked? = vault_key.present?

  # 404 rather than 403 throughout: a locked file that somebody cannot open
  # should not be confirmed to exist.
  def require_vault!
    return true if vault_unlocked?

    render_error(
      message: "The private section is locked.",
      code: "vault_locked",
      status: :forbidden
    )
    false
  end

  # The ordinary listings, which never contain anything private.
  #
  # Not "unless unlocked": the private section is a separate place, and the
  # screen says so — "nothing in here appears anywhere else in CloudVault".
  # Having it quietly reappear in My Files the moment the section is open would
  # make that untrue at the worst possible moment.
  def hide_locked(scope)
    scope.where(locked: false)
  end

  # The private section itself, which only exists while it is open.
  def only_locked(scope)
    vault_unlocked? ? scope.where(locked: true) : scope.none
  end
end
