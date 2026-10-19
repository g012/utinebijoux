require "test_helper"

class CheckoutTest < ActiveSupport::TestCase
  test "cart addition does not reserve inventory" do
    product = create_product
    cart_for(product)
    assert_equal 1, product.reload.stock_quantity
  end

  test "sold out inactive and archived products cannot be reserved" do
    [ { stock_quantity: 0 }, { active: false }, { archived: true } ].each do |attributes|
      assert_raises(Checkout::Unavailable) { reserve(create_product(**attributes)) }
    end
    assert_equal 0, Order.count
  end

  test "quantity exceeding stock rolls back the entire basket" do
    product = create_product
    cart = cart_for(product)
    unavailable = create_product(unique_piece: false, stock_quantity: 2)
    cart.cart_items.create!(product: unavailable, quantity: 3)
    assert_raises(Checkout::Unavailable) { Checkout.reserve(cart) }
    assert_equal 1, product.reload.stock_quantity
    assert_equal 2, cart.cart_items.count
    assert_equal 0, Order.count
  end

  test "a repeatable product reserves only the requested quantity" do
    product = create_product(unique_piece: false, stock_quantity: 4)
    order = reserve(product, quantity: 3)
    assert_equal 1, product.reload.stock_quantity
    assert_equal 3, order.order_items.first.quantity
    assert_equal product.price_cents * 3 + Shop.shipping_cents, order.total_cents
  end

  test "same cart retries reuse one order without reducing stock again" do
    product = create_product
    cart = cart_for(product)
    order = Checkout.reserve(cart)
    assert_equal order, Checkout.reserve(cart)
    assert_equal 1, Order.count
    assert_equal 0, product.reload.stock_quantity
  end

  test "snapshots are immutable and Stripe receives database prices" do
    product = create_product
    order = reserve(product)
    item = order.order_items.first
    product.update!(name: "Changed", price_cents: 9900)
    assert_equal "Bracelet Aurore", item.product_name
    assert_equal 2800, item.unit_price_cents
    assert_raises(ActiveRecord::ReadonlyAttributeError) { item.update!(unit_price_cents: 1) }
    assert_equal 2800, order.checkout_request.dig("line_items", 0, "price_data", "unit_amount")
    assert_equal [ "FR" ], order.checkout_request.dig("shipping_address_collection", "allowed_countries")
    assert_equal [ "card" ], order.checkout_request["payment_method_types"]
  end

  test "session expiration matches the local reservation and request key is stable" do
    order = reserve
    request = order.checkout_request.deep_symbolize_keys
    assert_in_delta 35.minutes, order.expires_at - Time.current, 2
    calls = []
    creator = lambda do |parameters, options|
      calls << [ parameters, options ]
      stripe_session(order, status: "open", payment_status: "unpaid")
    end
    Stripe::Checkout::Session.stub(:create, creator) { Checkout.session_for(order) }
    assert_equal request, calls.first.first
    assert_equal "checkout-#{order.public_token}", calls.first.last[:idempotency_key]
    assert_equal "cs_test_#{order.id}", order.reload.stripe_session_id
    assert_equal request[:expires_at], order.expires_at.to_i
  end

  test "definitive Stripe rejection releases exactly once" do
    order = reserve
    creator = ->(*) { raise Stripe::InvalidRequestError.new("Invalid request", nil) }
    Stripe::Checkout::Session.stub(:create, creator) do
      assert_raises(Stripe::InvalidRequestError) { Checkout.session_for(order) }
    end
    assert order.reload.cancelled?
    assert_equal 1, order.order_items.first.product.reload.stock_quantity
    order.with_lock { order.release!(:expired) }
    assert_equal 1, order.order_items.first.product.reload.stock_quantity
    assert_equal 1, order.cart.cart_items.count
    assert_equal 1, order.cart.cart_items.first.quantity
  end

  test "network uncertainty retains stock and retries the identical Stripe request" do
    order = reserve
    creator = ->(*) { raise Stripe::APIConnectionError, "Timeout" }
    original = order.checkout_request
    Stripe::Checkout::Session.stub(:create, creator) do
      assert_raises(Stripe::APIConnectionError) { Checkout.session_for(order) }
    end
    assert order.reload.pending_payment?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
    Stripe::Checkout::Session.stub(:create, ->(parameters, options) {
      assert_equal original, parameters.deep_stringify_keys
      assert_equal "checkout-#{order.public_token}", options[:idempotency_key]
      stripe_session(order, status: "open", payment_status: "unpaid")
    }) { Checkout.session_for(order) }
    assert order.reload.stripe_session_id.present?
  end
end
