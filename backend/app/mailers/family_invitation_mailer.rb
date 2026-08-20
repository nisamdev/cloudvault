# frozen_string_literal: true

class FamilyInvitationMailer < ApplicationMailer
  # The raw token is passed in rather than read from the record: only the digest
  # is persisted, so this is the one moment it can be put into a link.
  # accept_url is built by the caller, which knows how the browser reached us —
  # a link to localhost is no use to somebody reading it on their phone.
  def invite(invitation, accept_url)
    @invitation = invitation
    @family = invitation.family
    @inviter = invitation.invited_by
    @accept_url = accept_url

    mail(
      to: invitation.email,
      subject: "#{@inviter.full_name || @inviter.email} invited you to #{@family.name} on CloudVault"
    )
  end
end
