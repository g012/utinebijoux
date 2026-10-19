require "test_helper"

class StorefrontTest < ActionDispatch::IntegrationTest
  test "French storefront and public pages render" do
    product = create_product
    [ root_path, products_path, product_path(product), about_path, contact_path, legal_path("conditions-de-vente"), cart_path, sitemap_path ].each do |path|
      get path
      assert_response :success
    end
    get product_path(product)
    assert_select "html[lang=fr]"
    assert_select 'script[type="application/ld+json"]', /Bracelet Aurore/
    assert_select 'meta[property="og:title"]'
  end

  test "cart has secure anonymous identity and ignores forged prices" do
    product = create_product
    post cart_items_path, params: { product_id: product.id, quantity: 1, price_cents: 1, unit_price_cents: 1 }
    assert_redirected_to cart_path
    assert cookies[:cart_token].present?
    assert_equal 1, product.reload.stock_quantity
    order = nil
    Stripe::Checkout::Session.stub(:create, ->(parameters, *) {
      assert_equal 2800, parameters[:line_items].first[:price_data][:unit_amount]
      order = Order.last
      stripe_session(order, status: "open", payment_status: "unpaid")
    }) do
      post checkout_cart_path, params: { price_cents: 1, total_cents: 1, product_id: 99999 }
    end
    assert_redirected_to "https://checkout.stripe.com/c/test"
    assert_equal 2800 + Shop.shipping_cents, order.reload.total_cents
    assert_equal 0, product.reload.stock_quantity
  end

  test "unique quantity is bounded and another visitor cannot access the cart" do
    product = create_product
    post cart_items_path, params: { product_id: product.id, quantity: 2 }
    assert_equal 0, CartItem.count
    post cart_items_path, params: { product_id: product.id, quantity: 1 }
    item = CartItem.last
    another_visitor = open_session
    another_visitor.delete cart_item_path(item)
    another_visitor.assert_response :not_found
    assert CartItem.exists?(item.id)
  end

  test "sold item rejected with a friendly French message" do
    product = create_product(stock_quantity: 0)
    get product_path(product)
    assert_select "form[action=?]", cart_items_path, count: 0
    post cart_items_path, params: { product_id: product.id, quantity: 1 }
    follow_redirect!
    assert_select ".flash.alert", /Désolé/
    assert_equal 0, CartItem.count
  end

  test "a product sold after adding to cart is identified at checkout" do
    product = create_product
    post cart_items_path, params: { product_id: product.id, quantity: 1 }
    product.update!(stock_quantity: 0)
    post checkout_cart_path
    follow_redirect!
    assert_select ".flash.alert", /Désolé/
    assert_select ".unavailable", /Désolé/
    assert_equal 0, Order.count
  end

  test "success-page refresh never marks an unpaid order paid or changes stock" do
    order = reserve
    2.times { get order_path(order); assert_response :success }
    assert order.reload.pending_payment?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select 'meta[name=robots][content="noindex,nofollow"]'
    get "/commandes/#{order.id}"
    assert_response :not_found
  end

  test "webhook rejects invalid signatures and accepts signed duplicate delivery" do
    order = reserve
    event = stripe_event(order)
    payload = event.to_json
    post "/stripe/webhook", params: payload, headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "invalid" }
    assert_response :bad_request
    assert order.reload.pending_payment?
    signature = Stripe::Webhook::Signature.generate_header(Time.now,
      Stripe::Webhook::Signature.compute_signature(Time.now, payload, ENV.fetch("STRIPE_WEBHOOK_SECRET")))
    2.times do
      post "/stripe/webhook", params: payload, headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => signature }
      assert_response :success
    end
    assert order.reload.paid?
    assert_equal 0, order.order_items.first.product.reload.stock_quantity
    assert_equal 1, StripeEvent.count
  end
end
