require "test_helper"

class StripeCheckoutEventTest < ActiveSupport::TestCase
  test "paid webhook consumes the existing reservation exactly once" do
    order = reserve
    event = stripe_event(order)
    assert_enqueued_with(job: SendOrderConfirmationJob) { StripeCheckoutEvent.call(event) }
    assert order.reload.paid?
    assert_equal "client@example.com", order.customer_email
    assert_equal "Paris", order.shipping_details.dig("address", "city")
    assert_equal "pi_test_#{order.id}", order.stripe_payment_intent_id
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
    assert_no_enqueued_jobs { 2.times { StripeCheckoutEvent.call(event) } }
    assert_equal 1, StripeEvent.count
    StripeCheckoutEvent.call(stripe_event(order))
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
  end

  test "unpaid completed sessions are not marked paid" do
    order = reserve
    StripeCheckoutEvent.call(stripe_event(order, payment_status: "unpaid"))
    assert order.reload.pending_payment?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
    StripeCheckoutEvent.call(stripe_event(order, type: "checkout.session.async_payment_succeeded"))
    assert order.reload.paid?
  end

  test "expiry and final failure restore stock only once even with distinct events" do
    [ "checkout.session.expired", "checkout.session.async_payment_failed" ].each do |type|
      order = reserve
      2.times { StripeCheckoutEvent.call(stripe_event(order, type: type, status: "expired", payment_status: "unpaid")) }
      assert_not order.reload.pending_payment?
      assert order.released_at
      assert_equal 1, order.order_items.first.product.reload.stock_quantity
    end
  end

  test "late expiry cannot release a paid order" do
    order = reserve
    StripeCheckoutEvent.call(stripe_event(order))
    StripeCheckoutEvent.call(stripe_event(order, type: "checkout.session.expired", status: "expired", payment_status: "unpaid"))
    assert order.reload.paid?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
  end

  test "wrong session amount currency and reference are rejected" do
    order = reserve
    order.update!(stripe_session_id: "cs_expected")
    [ { id: "cs_other" }, { id: "cs_expected", amount_total: 1 }, { id: "cs_expected", currency: "usd" }, { id: "cs_expected", client_reference_id: "other" } ].each do |override|
      assert_raises(StripeCheckoutEvent::Mismatch) { StripeCheckoutEvent.call(stripe_event(order, **override)) }
    end
    assert order.reload.pending_payment?
    assert_equal 0, StripeEvent.count
  end

  test "payment after release raises an explicit reconciliation error" do
    order = reserve
    order.with_lock { order.release!(:expired) }
    assert_raises(StripeCheckoutEvent::Mismatch) { StripeCheckoutEvent.call(stripe_event(order)) }
    assert order.reload.expired?
  end

  test "signed payment event can recover a lost session creation response" do
    order = reserve
    assert_nil order.stripe_session_id
    StripeCheckoutEvent.call(stripe_event(order))
    assert order.reload.paid?
    assert_equal "cs_test_#{order.id}", order.stripe_session_id
  end
end
