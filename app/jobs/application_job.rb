class ApplicationJob < ActiveJob::Base
  self.enqueue_after_transaction_commit = false
end
