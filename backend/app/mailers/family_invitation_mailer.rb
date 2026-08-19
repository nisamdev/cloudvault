# frozen_string_literal: true

class FamilyInvitationMailer < ApplicationMailer
  # The raw token is passed in rather than read from the record: only the digest
  # is persisted, so this is the one moment it can be put into a link.
  def invite(invitation, raw_token)
    @invitation = invitation
    @family = invitation.family
    @inviter = invitation.invited_by
    @accept_url = "#{Rails.configuration.x.app_url}/invitations/#{raw_token}"

    mail(
      to: invitation.email,
      subject: "#{@inviter.full_name || @inviter.email} invited you to #{@family.name} on CloudVault"
    )
  end
end
