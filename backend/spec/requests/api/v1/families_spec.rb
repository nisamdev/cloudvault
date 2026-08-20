require "rails_helper"

RSpec.describe "Api::V1::Families" do
  let(:owner) { create(:user) }
  let(:stranger) { create(:user) }

  describe "POST /api/v1/families" do
    it "creates a family and makes the caller its owner" do
      post "/api/v1/families",
           params: { family: { name: "The Smith Family", description: "Ours" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json["family"]["name"]).to eq("The Smith Family")
      expect(json["family"]["role"]).to eq("owner")
      expect(owner.reload.primary_membership.role).to eq("owner")
    end

    it "refuses when the caller already belongs to a family" do
      create(:family, owner: owner)

      post "/api/v1/families",
           params: { family: { name: "Second Family" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["error"]["code"]).to eq("family_exists")
    end

    it "validates the name" do
      post "/api/v1/families", params: { family: { name: "" } },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/families/:id" do
    let!(:family) { create(:family, owner: owner) }
    let!(:member) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }

    it "returns the family with its members" do
      get "/api/v1/families/#{family.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json["members"].size).to eq(2)
      expect(json["members"].map { |m| m["role"] }).to contain_exactly("owner", "editor")
    end

    it "hides the family from non-members with a 404" do
      get "/api/v1/families/#{family.id}", headers: auth_headers_for(stranger)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/families/:id" do
    let!(:family) { create(:family, owner: owner) }
    let!(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }

    it "lets the owner rename the family" do
      patch "/api/v1/families/#{family.id}",
            params: { family: { name: "Renamed" } },
            headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(family.reload.name).to eq("Renamed")
    end

    it "refuses an editor" do
      patch "/api/v1/families/#{family.id}",
            params: { family: { name: "Nope" } },
            headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/families/:family_id/invitations" do
    let!(:family) { create(:family, owner: owner) }
    let!(:editor) { create(:user).tap { |u| create(:family_member, family: family, user: u, role: "editor") } }

    it "creates an invitation and emails it" do
      expect {
        post "/api/v1/families/#{family.id}/invitations",
             params: { email: "gran@smith.com", role: "viewer" },
             headers: auth_headers_for(owner), as: :json
      }.to change(FamilyInvitation, :count).by(1)
        .and have_enqueued_job(ActionMailer::MailDeliveryJob)

      expect(response).to have_http_status(:created)
      expect(json["invitation"]["email"]).to eq("gran@smith.com")
    end

    # This is a vault someone runs at home, where SMTP may not be configured at
    # all, so the inviter is given the link to pass on themselves. It is handed
    # back exactly once, to the admin who just created it — the same bargain a
    # share link makes.
    it "returns the link once, to whoever created it" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: "gran@smith.com" },
           headers: auth_headers_for(owner), as: :json

      expect(json["invitation"]["accept_url"]).to include("/invitations/")
      expect(FamilyInvitation.last.token_digest).to be_present
    end

    it "still stores only a digest, and never exposes it" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: "gran@smith.com" },
           headers: auth_headers_for(owner), as: :json

      invitation = FamilyInvitation.last
      token = json["invitation"]["accept_url"].split("/invitations/").last

      expect(invitation.token_digest).to eq(FamilyInvitation.digest_for(token))
      expect(invitation.attributes.values).not_to include(token)
      expect(response.body).not_to include(invitation.token_digest)
    end

    it "does not hand the link to anyone who asks for it later" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: "gran@smith.com" },
           headers: auth_headers_for(owner), as: :json
      token = json["invitation"]["accept_url"].split("/invitations/").last

      get "/api/v1/families/#{family.id}", headers: auth_headers_for(owner)

      expect(response.body).not_to include(token)
    end

    # A link to localhost is no use to somebody reading it on their phone.
    it "builds the link for the origin the browser actually used" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: "gran@smith.com" },
           headers: auth_headers_for(owner).merge("Origin" => "https://vault.example.com"),
           as: :json

      expect(json["invitation"]["accept_url"]).to start_with("https://vault.example.com/invitations/")
    end

    it "refuses an editor — inviting is admin-only" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: "gran@smith.com" },
           headers: auth_headers_for(editor), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to invite an existing member" do
      post "/api/v1/families/#{family.id}/invitations",
           params: { email: editor.email },
           headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["error"]["code"]).to eq("already_member")
    end

    it "replaces an outstanding invitation rather than colliding" do
      2.times do
        post "/api/v1/families/#{family.id}/invitations",
             params: { email: "gran@smith.com" },
             headers: auth_headers_for(owner), as: :json
        expect(response).to have_http_status(:created)
      end

      expect(family.family_invitations.pending.where(email: "gran@smith.com").count).to eq(1)
    end
  end

  describe "invitation acceptance" do
    let!(:family) { create(:family, owner: owner) }
    let(:invitation) do
      family.family_invitations.create!(email: "gran@smith.com", role: "viewer", invited_by: owner)
    end
    let(:token) { invitation.raw_token }
    let!(:gran) { create(:user, email: "gran@smith.com") }

    it "shows who invited you before you sign in" do
      get "/api/v1/invitations/#{token}"

      expect(response).to have_http_status(:ok)
      expect(json["invitation"]["family_name"]).to eq(family.name)
      expect(json["invitation"]["role"]).to eq("viewer")
    end

    it "404s on an unknown token" do
      get "/api/v1/invitations/not-a-real-token"

      expect(response).to have_http_status(:not_found)
    end

    it "adds the invitee to the family" do
      expect {
        post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(gran)
      }.to change { family.family_members.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(gran.reload.primary_membership.role).to eq("viewer")
      expect(invitation.reload.accepted_at).to be_present
    end

    it "refuses acceptance from a different account than it was sent to" do
      other = create(:user, email: "someone.else@example.com")

      post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(other)

      expect(response).to have_http_status(:forbidden)
      expect(json["error"]["code"]).to eq("invitation_email_mismatch")
    end

    it "cannot be accepted twice" do
      post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(gran)
      post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(gran)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an expired invitation" do
      invitation.update!(expires_at: 1.day.ago)

      post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(gran)

      expect(response).to have_http_status(:not_found)
      expect(json["error"]["code"]).to eq("invalid_invitation")
    end

    it "refuses a revoked invitation" do
      invitation.update!(revoked_at: Time.current)

      post "/api/v1/invitations/#{token}/accept", headers: auth_headers_for(gran)

      expect(response).to have_http_status(:not_found)
    end

    it "requires sign-in to accept" do
      post "/api/v1/invitations/#{token}/accept"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
