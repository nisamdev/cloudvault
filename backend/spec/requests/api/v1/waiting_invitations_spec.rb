require "rails_helper"

# An invitation to somebody who already has an account used to exist only as a
# link in an email. If they never opened it, nothing in the app knew they had
# been asked.
RSpec.describe "Api::V1::Invitations waiting for me" do
  let(:family) { create(:family) }
  let(:inviter) { family.owner }
  let(:invitee) { create(:user, email: "sister@smith.com") }

  def invite(email: invitee.email, role: "editor")
    create(:family_invitation, family: family, invited_by: inviter, email: email, role: role)
  end

  describe "seeing what is waiting" do
    it "lists an invitation addressed to me" do
      invite

      get "/api/v1/invitations/mine", headers: auth_headers_for(invitee)

      row = json["invitations"].first
      expect(row["family"]["name"]).to eq(family.name)
      expect(row["role"]).to eq("editor")
      expect(row["invited_by"]).to eq(inviter.full_name || inviter.email)
    end

    it "does not list somebody else's" do
      invite(email: "someone@else.com")

      get "/api/v1/invitations/mine", headers: auth_headers_for(invitee)

      expect(json["invitations"]).to be_empty
    end

    # Only one of these can exist at a time: a pending invitation to one person
    # is unique per family, so each is answered before the next is sent.
    %i[revoked_at accepted_at declined_at].each do |answered|
      it "does not list one that was #{answered.to_s.delete_suffix('_at')}" do
        invite.update!(answered => Time.current)

        get "/api/v1/invitations/mine", headers: auth_headers_for(invitee)

        expect(json["invitations"]).to be_empty
      end
    end

    it "does not list one that has run out" do
      invite.update!(expires_at: 1.day.ago)

      get "/api/v1/invitations/mine", headers: auth_headers_for(invitee)

      expect(json["invitations"]).to be_empty
    end

    # The token proves somebody controls a mailbox before they have an account.
    # Signed in as the address it was sent to, it proves nothing further.
    it "needs no token, only the right account" do
      waiting = invite

      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(waiting.reload.accepted_at).to be_present
    end

    it "refuses one addressed to somebody else, by id" do
      waiting = invite(email: "someone@else.com")

      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:not_found)
      expect(waiting.reload.accepted_at).to be_nil
    end
  end

  describe "answering" do
    # Belonging to one family does not stop you joining another. This was the
    # last place in the app still refusing.
    it "joins an account that is already in a family of its own" do
      own = create(:family, owner: invitee)
      create(:stored_file, user: invitee, family: own)
      waiting = invite

      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:created)
      expect(invitee.reload.families.map(&:id)).to contain_exactly(own.id, family.id)
    end

    it "shows the family just joined" do
      waiting = invite

      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(invitee.reload.current_family_id).to eq(family.id)
    end

    it "will not join the same family twice" do
      create(:family_member, family: family, user: invitee, role: "viewer")
      waiting = invite

      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:conflict)
    end

    it "takes no for an answer" do
      waiting = invite

      post "/api/v1/invitations/mine/#{waiting.id}/decline", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:no_content)
      expect(waiting.reload.declined_at).to be_present
      expect(family.family_members.exists?(user_id: invitee.id)).to be(false)
    end

    # Declining is an answer; cancelling is the inviter changing their mind.
    # Both stop it pending, and only one is worth reporting.
    it "keeps declining apart from being cancelled" do
      waiting = invite
      post "/api/v1/invitations/mine/#{waiting.id}/decline", headers: auth_headers_for(invitee)

      expect(waiting.reload).to be_declined
      expect(waiting.revoked_at).to be_nil
    end

    it "cannot be answered twice" do
      waiting = invite
      post "/api/v1/invitations/mine/#{waiting.id}/decline", headers: auth_headers_for(invitee)
      post "/api/v1/invitations/mine/#{waiting.id}/accept", headers: auth_headers_for(invitee)

      expect(response).to have_http_status(:not_found)
    end

    # Saying no once must not mean never being asked again — which is exactly
    # what the pending-invitation index did until it was taught about it.
    it "lets them be asked again after they decline" do
      waiting = invite
      post "/api/v1/invitations/mine/#{waiting.id}/decline", headers: auth_headers_for(invitee)

      expect { invite }.to change(FamilyInvitation, :count).by(1)
    end
  end

  it "says nothing to somebody who is not signed in" do
    get "/api/v1/invitations/mine"

    expect(response).to have_http_status(:unauthorized)
  end
end
