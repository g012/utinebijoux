ENV["RAILS_ENV"] ||= "test"
ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key"
ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_only"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
Stripe.api_key = "sk_test_not_a_real_key"
require_relative "test_helpers/session_test_helper"

class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  fixtures :all

  def create_product(**attributes)
    Product.create!({ name: "Bracelet Aurore", description: "Perles de verre, assemblées à la main.", price_cents: 2800 }.merge(attributes))
  end

  def cart_for(product, quantity: 1)
    Cart.create!.tap { |cart| cart.cart_items.create!(product: product, quantity: quantity) }
  end

  def reserve(product = create_product, quantity: 1)
    Checkout.reserve(cart_for(product, quantity: quantity))
  end

  def stripe_session(order, **overrides)
    Stripe::Checkout::Session.construct_from({
      id: "cs_test_#{order.id}", object: "checkout.session", status: "complete", payment_status: "paid",
      amount_total: order.total_cents, currency: order.currency, client_reference_id: order.number,
      metadata: { order_token: order.public_token }, expires_at: order.expires_at.to_i,
      url: "https://checkout.stripe.com/c/test", payment_intent: "pi_test_#{order.id}", customer: "cus_test",
      customer_details: { email: "client@example.com", name: "Camille", address: { city: "Paris", country: "FR" } },
      collected_information: { shipping_details: { name: "Camille", address: { line1: "1 rue de Test", postal_code: "75001", city: "Paris", country: "FR" } } }
    }.merge(overrides))
  end

  def stripe_event(order, type: "checkout.session.completed", event_id: "evt_test_#{SecureRandom.hex(8)}", **overrides)
    Stripe::Event.construct_from(id: event_id, object: "event", type: type, data: { object: stripe_session(order, **overrides).to_hash })
  end
end
