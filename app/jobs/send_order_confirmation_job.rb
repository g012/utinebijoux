class SendOrderConfirmationJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 10
  def perform(order)
    order.with_lock do
      return unless order.paid? && order.confirmation_enqueued_at.nil?
      # Solid Queue uses the same PostgreSQL database: these enqueues and this
      # marker commit atomically. SMTP itself remains at-least-once delivery.
      OrderMailer.confirmation(order).deliver_later
      OrderMailer.new_sale(order).deliver_later
      order.update!(confirmation_enqueued_at: Time.current)
    end
  end
end
