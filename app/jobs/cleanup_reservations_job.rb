class CleanupReservationsJob < ApplicationJob
  retry_on Stripe::StripeError, wait: :polynomially_longer, attempts: 10
  def perform
    Order.awaiting_cleanup.find_each do |order|
      begin
        ReconcileCheckout.call(order)
      rescue Stripe::StripeError, StripeCheckoutEvent::Mismatch => error
        Rails.logger.error("Checkout reconciliation failed for #{order.number}: #{error.class}")
        Rails.error.report(error, context: { order_number: order.number })
        # Continue other orders; the next scheduled run retries this one.
      end
    end
    Order.where(status: "paid", confirmation_enqueued_at: nil).find_each do |order|
      SendOrderConfirmationJob.perform_later(order)
    end
  end
end
