# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.configuration.x.mail_from }
  layout "mailer"
end
