class TransactionalMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.enqueue_after_transaction_commit = false
end
