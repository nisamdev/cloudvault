require "rails_helper"

RSpec.describe SendExpiryRemindersJob do
  let(:user) { create(:user, email: "dad@example.com", full_name: "Dad Smith") }
  let!(:family) { create(:family, owner: user) }

  def record(type:, field:, days:, owner: user, visibility: "private", title: "The permit")
    create(:vault_record,
           user: owner, record_type: type, title: title,
           visibility: visibility,
           family: visibility == "family" ? family : nil,
           data: { field => days.days.from_now.to_date.iso8601 })
  end

  def run = described_class.new.perform

  describe "what it writes about" do
    it "writes when a date crosses a step of its schedule" do
      record(type: "immigration", field: "expires_on", days: 170)

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include("The permit")
    end

    it "says nothing while the date is further out than the first step" do
      record(type: "immigration", field: "expires_on", days: 300)

      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
    end

    # A subscription's next charge comes round every month; mailing about it
    # would be noise you learn to filter.
    it "stays quiet about dates that only count down on screen" do
      record(type: "subscription", field: "next_charge_on", days: 3)

      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it "writes about the one you cannot afford to miss" do
      record(type: "subscription", field: "cancel_by", days: 5)

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "says nothing about a date that has already gone" do
      record(type: "immigration", field: "expires_on", days: -5)

      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "not saying it twice" do
    it "writes once and then leaves it alone" do
      record(type: "immigration", field: "expires_on", days: 170)

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it "writes again once the next step down is reached" do
      permit = record(type: "immigration", field: "expires_on", days: 170)
      run

      permit.update!(data: { "expires_on" => 80.days.from_now.to_date.iso8601 })

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    # Renewing something is exactly when the whole schedule should start again.
    it "starts over when the date is moved" do
      permit = record(type: "immigration", field: "expires_on", days: 170)
      run

      permit.update!(data: { "expires_on" => 175.days.from_now.to_date.iso8601 })

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end
  end

  describe "one letter, not five" do
    it "gathers everything of one person's into a single message" do
      record(type: "immigration", field: "expires_on", days: 170)
      create(:vault_record, user: user, record_type: "vehicle", title: "The Golf",
                            data: { "mot_due_on" => 20.days.from_now.to_date.iso8601 })

      expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.body.encoded).to include("The permit").and include("The Golf")
      expect(mail.subject).to match(/and 1 other/)
    end

    # Read on a lock screen, the subject should be the whole reminder.
    it "puts the most urgent thing in the subject" do
      record(type: "vehicle", field: "mot_due_on", days: 3, title: "The Golf")

      run
      expect(ActionMailer::Base.deliveries.last.subject).to include("in 3 days")
    end
  end

  describe "whose records" do
    let!(:partner) { create(:user, email: "mum@example.com") }

    before { create(:family_member, family: family, user: partner, role: "editor") }

    it "writes to the household about what the household shares" do
      record(type: "immigration", field: "expires_on", days: 170, visibility: "family")

      run
      expect(ActionMailer::Base.deliveries.map(&:to).flatten)
        .to include("dad@example.com", "mum@example.com")
    end

    it "keeps a private record to the person who added it" do
      record(type: "immigration", field: "expires_on", days: 170)

      run
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq([ "dad@example.com" ])
    end

    it "leaves out the household's records for somebody who only wants their own" do
      partner.update!(reminder_scope: "own")
      record(type: "immigration", field: "expires_on", days: 170, visibility: "family")

      run
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).not_to include("mum@example.com")
    end
  end

  describe "the switch" do
    it "writes nothing to somebody who turned reminders off" do
      user.update!(reminders_enabled: false)
      record(type: "immigration", field: "expires_on", days: 170)

      expect { run }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  it "does not let one bad address stop the rest of the household" do
    partner = create(:user, email: "mum@example.com")
    create(:family_member, family: family, user: partner, role: "editor")
    record(type: "immigration", field: "expires_on", days: 170, visibility: "family")

    allow(ExpiryReminderMailer).to receive(:upcoming).and_wrap_original do |original, recipient, *rest|
      raise Net::SMTPFatalError, "no such mailbox" if recipient.email == "dad@example.com"

      original.call(recipient, *rest)
    end

    expect { run }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "mum@example.com" ])
  end
end
