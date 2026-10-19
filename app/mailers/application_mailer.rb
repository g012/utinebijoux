class ApplicationMailer < ActionMailer::Base
  helper ApplicationHelper
  default from: -> { Shop.email }
  self.delivery_job = TransactionalMailDeliveryJob
  layout "mailer"
end
