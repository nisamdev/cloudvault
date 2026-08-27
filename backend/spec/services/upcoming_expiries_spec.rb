require "rails_helper"

RSpec.describe UpcomingExpiries do
  let(:user) { create(:user) }
  let!(:family) { create(:family, owner: user) }

  def record(type:, field:, days:, owner: user)
    create(:vault_record, user: owner, record_type: type, title: "#{type} thing",
                          data: { field => days.days.from_now.to_date.iso8601 })
  end

  describe "what the screen shows" do
    it "lists dates soonest first" do
      record(type: "vehicle", field: "mot_due_on", days: 40)
      record(type: "subscription", field: "cancel_by", days: 5)

      expect(described_class.for_user(user).map(&:days)).to eq([ 5, 40 ])
    end

    it "keeps showing something that has just run out" do
      record(type: "vehicle", field: "mot_due_on", days: -10)

      expect(described_class.for_user(user).map(&:days)).to eq([ -10 ])
    end

    it "forgets something that ran out long ago" do
      record(type: "vehicle", field: "mot_due_on", days: -400)

      expect(described_class.for_user(user)).to be_empty
    end

    it "shows dates that only count down, alongside the ones that write" do
      record(type: "subscription", field: "next_charge_on", days: 6)

      shown = described_class.for_user(user)
      expect(shown.size).to eq(1)
      expect(shown.first.field.reminds?).to be(false)
    end
  end

  # The settings screen shows this list and says how many of them will be
  # written about. A window narrower than the longest runway would promise a
  # letter about something it had never listed.
  describe "the screen and the post agreeing" do
    it "looks at least as far ahead as the longest reminder schedule" do
      longest = RecordTemplates::ALL
                .flat_map { |t| t.reminding_fields.flat_map { |f| f.remind.to_a } }
                .max

      expect(described_class::SHOWN_WITHIN_DAYS).to be >= longest
    end

    it "shows everything it would write about" do
      record(type: "immigration", field: "expires_on", days: 170)
      record(type: "vehicle", field: "mot_due_on", days: 20)

      shown = described_class.for_user(user).map { |d| [ d.record.id, d.field.key ] }
      writing = described_class.to_send(user).map { |d| [ d.record.id, d.field.key ] }

      expect(shown).to include(*writing)
    end
  end

  describe "whose records" do
    let(:partner) { create(:user) }

    before { create(:family_member, family: family, user: partner, role: "editor") }

    it "includes what the household shares" do
      shared = create(:vault_record, user: user, record_type: "vehicle", visibility: "family",
                                     family: family, title: "The Golf",
                                     data: { "mot_due_on" => 20.days.from_now.to_date.iso8601 })

      expect(described_class.for_user(partner).map { |d| d.record.id }).to include(shared.id)
    end

    it "leaves out somebody else's private record" do
      record(type: "vehicle", field: "mot_due_on", days: 20, owner: create(:user))

      expect(described_class.for_user(partner)).to be_empty
    end

    it "narrows to their own when that is what they asked for" do
      partner.update!(reminder_scope: "own")
      create(:vault_record, user: user, record_type: "vehicle", visibility: "family",
                            family: family, data: { "mot_due_on" => 20.days.from_now.to_date.iso8601 })

      expect(described_class.to_send(partner)).to be_empty
    end
  end

  it "ignores a date it cannot read rather than failing the whole run" do
    create(:vault_record, user: user, record_type: "vehicle",
                          data: { "mot_due_on" => "next spring sometime" })

    expect { described_class.for_user(user) }.not_to raise_error
    expect(described_class.for_user(user)).to be_empty
  end
end
