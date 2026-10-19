require "test_helper"

class CleanupReservationsJobTest < ActiveSupport::TestCase
  test "clock expiry alone never releases inventory when Stripe is unreachable" do
    order = reserve
    order.update!(stripe_session_id: "cs_test")
    travel_to 1.hour.from_now do
      Stripe::Checkout::Session.stub(:retrieve, ->(*) { raise Stripe::APIConnectionError, "Timeout" }) do
        CleanupReservationsJob.perform_now
      end
    end
    assert order.reload.pending_payment?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
  end

  test "cleanup expires an open Stripe session before releasing once" do
    order = reserve
    order.update!(stripe_session_id: "cs_test_#{order.id}")
    Stripe::Checkout::Session.stub(:retrieve, stripe_session(order, status: "open", payment_status: "unpaid")) do
      Stripe::Checkout::Session.stub(:expire, stripe_session(order, status: "expired", payment_status: "unpaid")) do
        travel_to(1.hour.from_now) { 2.times { CleanupReservationsJob.perform_now } }
      end
    end
    assert order.reload.expired?
    assert_equal 1, order.order_items.first.product.reload.stock_quantity
  end

  test "cleanup discovers payment instead of returning stock" do
    order = reserve
    order.update!(stripe_session_id: "cs_test_#{order.id}")
    Stripe::Checkout::Session.stub(:retrieve, stripe_session(order)) do
      travel_to(1.hour.from_now) { CleanupReservationsJob.perform_now }
    end
    assert order.reload.paid?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
  end

  test "a complete unpaid session keeps its reservation" do
    order = reserve
    order.update!(stripe_session_id: "cs_test_#{order.id}")
    Stripe::Checkout::Session.stub(:retrieve, stripe_session(order, payment_status: "unpaid")) do
      ReconcileCheckout.call(order, cancel: true)
    end
    assert order.reload.pending_payment?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
  end

  test "missing session is found after lost creation response even beyond expiry" do
    order = reserve
    list = Object.new
    list.define_singleton_method(:auto_paging_each) { [ @session ].each }
    list.instance_variable_set(:@session, stripe_session(order, status: "expired", payment_status: "unpaid"))
    Stripe::Checkout::Session.stub(:list, list) do
      Stripe::Checkout::Session.stub(:retrieve, stripe_session(order, status: "expired", payment_status: "unpaid")) do
        travel_to(1.hour.from_now) { CleanupReservationsJob.perform_now }
      end
    end
    assert order.reload.expired?
    assert_equal "cs_test_#{order.id}", order.stripe_session_id
    assert_equal 1, order.order_items.first.product.reload.stock_quantity
  end

  test "no remotely created session permits release after a successful Stripe lookup" do
    order = reserve
    list = Object.new
    list.define_singleton_method(:auto_paging_each) { [].each }
    Stripe::Checkout::Session.stub(:list, list) do
      travel_to(1.hour.from_now) { CleanupReservationsJob.perform_now }
    end
    assert order.reload.expired?
    assert_equal 1, order.order_items.first.product.reload.stock_quantity
  end

  test "confirmation jobs enqueue both emails once" do
    order = reserve
    StripeCheckoutEvent.call(stripe_event(order))
    assert_enqueued_emails 2 do
      2.times { SendOrderConfirmationJob.perform_now(order) }
    end
    assert order.reload.confirmation_enqueued_at
    assert_includes OrderMailer.confirmation(order).body.to_s, order.number
    assert_includes OrderMailer.new_sale(order).body.to_s, "Camille"
  end
end
