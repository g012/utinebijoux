# Never release a reservation solely because the local clock elapsed.
# An unavailable Stripe API means retaining stock and retrying safely.
class ReconcileCheckout
  def self.call(order, cancel: false)
    Checkout.session_for(order) unless order.stripe_session_id
    order.with_lock do
      return unless order.pending_payment?
      session = Stripe::Checkout::Session.retrieve(order.stripe_session_id)
      if session.status == "open"
        session = Stripe::Checkout::Session.expire(session.id)
      end
      payload = session.to_hash.deep_stringify_keys
      if session.status == "expired"
        order.release!(cancel ? :cancelled : :expired)
      elsif session.status == "complete" && session.payment_status == "paid"
        StripeCheckoutEvent.apply(order, payload, "checkout.session.completed")
      end
      # A completed, unpaid delayed payment retains stock pending its final event.
    end
  end
end
