require "rails_helper"

RSpec.describe "Api::V1 accepting an invitation" do
  let(:owner) { create(:user) }
  let!(:family) { create(:family, owner: owner) }
  let(:invitee) { create(:user, email: "gran@smith.com") }

  def invite(email: invitee.email, role: "editor")
    family.family_invitations.create!(email: email, role: role, invited_by: owner)
  end

  it "puts them in the family with the role they were given" do
    invitation = invite(role: "admin")

    post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

    expect(response).to have_http_status(:created)
    expect(family.family_members.find_by(user_id: invitee.id).role).to eq("admin")
  end

  it "refuses an account the invitation was not addressed to" do
    invitation = invite(email: "someone@else.com")

    post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

    expect(response).to have_http_status(:forbidden)
    expect(family.family_members.where(user_id: invitee.id)).to be_empty
  end

  # Registering to accept an invitation used to walk people through "create your
  # family" first, so they arrived back holding an empty one and were told they
  # already belonged somewhere.
  describe "when they were made to create a family on the way in" do
    let!(:accidental) { create(:family, owner: invitee, name: "Smith") }

    it "discards the empty one and joins the real family" do
      invitation = invite

      post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(Family.exists?(accidental.id)).to be false
      expect(invitee.reload.family_memberships.pluck(:family_id)).to eq([ family.id ])
    end

    # Joining a second family no longer means leaving the first: an account has
    # stood in any number of them since accounts stopped requiring one. What is
    # discarded is only the empty artefact above, never a family with a life of
    # its own.
    it "keeps a family that has anything in it, and joins anyway" do
      create(:stored_file, user: invitee, family: accidental)
      invitation = invite

      post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(Family.exists?(accidental.id)).to be true
      expect(invitee.reload.family_memberships.pluck(:family_id))
        .to contain_exactly(accidental.id, family.id)
    end

    it "keeps a family that somebody else has joined" do
      create(:family_member, family: accidental, user: create(:user), role: "editor")
      invitation = invite

      post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(Family.exists?(accidental.id)).to be true
    end

    it "keeps a family that has folders, even with no files yet" do
      create(:folder, user: invitee, family: accidental, name: "Passports")
      invitation = invite

      post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(Family.exists?(accidental.id)).to be true
    end

    # The family you have just joined is the one you meant to be working in.
    it "shows the new family after joining" do
      create(:stored_file, user: invitee, family: accidental)
      invitation = invite

      post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

      expect(invitee.reload.current_family_id).to eq(family.id)
    end
  end

  it "refuses an invitation that has been cancelled" do
    invitation = invite
    invitation.update!(revoked_at: Time.current)

    post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

    expect(response).to have_http_status(:not_found)
  end

  it "cannot be accepted twice" do
    invitation = invite

    post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)
    post "/api/v1/invitations/#{invitation.raw_token}/accept", headers: auth_headers_for(invitee)

    expect(response).to have_http_status(:not_found)
    expect(family.family_members.where(user_id: invitee.id).count).to eq(1)
  end
end
