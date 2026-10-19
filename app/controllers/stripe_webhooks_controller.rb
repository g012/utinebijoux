class StripeWebhooksController < ActionController::Base
  skip_forgery_protection
  def create
    event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], ENV.fetch("STRIPE_WEBHOOK_SECRET"))
    StripeCheckoutEvent.call(event)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  rescue StripeCheckoutEvent::Mismatch, ActiveRecord::RecordNotFound => error
    Rails.error.report(error)
    head :unprocessable_entity
  end
end
