class StripeCheckoutEvent
  class Mismatch < StandardError; end
  TYPES = %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.async_payment_failed checkout.session.expired].freeze

  def self.call(event)
    return unless TYPES.include?(event.type)
    session = event.data.object.to_hash.deep_stringify_keys
    order = Order.find_by!(public_token: session.dig("metadata", "order_token"))
    order.with_lock do
      return if StripeEvent.exists?(stripe_id: event.id)
      raise Mismatch, "Unexpected Checkout session" if order.stripe_session_id.present? && order.stripe_session_id != session["id"]
      if session["amount_total"] != order.total_cents || session["currency"] != order.currency || session["client_reference_id"] != order.number
        raise Mismatch, "Checkout amount, currency or reference mismatch"
      end
      order.update!(stripe_session_id: session.fetch("id")) if order.stripe_session_id.nil?
      apply(order, session, event.type)
      StripeEvent.create!(stripe_id: event.id, event_type: event.type)
    end
  end

  def self.apply(order, session, type)
    case type
    when "checkout.session.completed", "checkout.session.async_payment_succeeded"
      return unless session["payment_status"] == "paid"
      return if order.paid? || order.refunded?
      # A terminal locally released reservation must never silently be sold again.
      raise Mismatch, "Payment after reservation release; investigate in Stripe" unless order.pending_payment?
      order.update!(status: :paid, paid_at: Time.current,
        stripe_payment_intent_id: session["payment_intent"], stripe_customer_id: session["customer"],
        customer_email: session.dig("customer_details", "email"), customer_name: session.dig("customer_details", "name"),
        customer_details: session["customer_details"] || {},
        shipping_details: session.dig("collected_information", "shipping_details") || session["shipping_details"] || {})
    when "checkout.session.expired"
      raise Mismatch, "Session is not expired" unless session["status"] == "expired"
      order.release!(:expired)
    when "checkout.session.async_payment_failed"
      order.release!(:cancelled)
    end
  end
end
