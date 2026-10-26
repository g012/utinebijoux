require "test_helper"

class SizedCheckoutTest < ActiveSupport::TestCase
  setup do
    @product = create_product(name: "Bracelet citrons", price_cents: 600, unique_piece: false)
    @small = @product.product_sizes.create!(size_cm: 15)
    @large = @product.product_sizes.create!(size_cm: 18)
  end

  def sized_cart(size = @small, quantity: 1)
    Cart.create!.tap { |cart| cart.cart_items.create!(product: @product, product_size: size, quantity: quantity) }
  end

  test "reservation consumes only the chosen size and snapshots it for Stripe and emails" do
    order = Checkout.reserve(sized_cart)
    assert_equal 0, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    assert_equal 1, @product.reload.available_stock
    item = order.order_items.first
    assert_equal @small, item.product_size
    assert_equal 15, item.size_cm
    assert_equal "Bracelet citrons — 15 cm", item.display_name
    assert_equal "Bracelet citrons — 15 cm", order.checkout_request.dig("line_items", 0, "price_data", "product_data", "name")
    assert_equal 600, order.checkout_request.dig("line_items", 0, "price_data", "unit_amount")
    @product.update!(name: "Un autre nom", price_cents: 900)
    assert_equal "Bracelet citrons — 15 cm", item.reload.display_name
    assert_raises(ActiveRecord::ReadonlyAttributeError) { item.size_cm = 18 }
    order.update!(customer_email: "test@example.com")
    assert_includes OrderMailer.confirmation(order).body.to_s, "Bracelet citrons — 15 cm"
    assert_includes OrderMailer.new_sale(order).body.to_s, "Bracelet citrons — 15 cm"
  end

  test "two sizes of the same bracelet remain distinct cart and order lines" do
    cart = sized_cart
    cart.cart_items.create!(product: @product, product_size: @large)
    assert_equal 2, cart.cart_items.count
    order = Checkout.reserve(cart)
    assert_equal [ 15, 18 ], order.order_items.order(:size_cm).pluck(:size_cm)
    assert_equal 1200, order.subtotal_cents
    assert_equal 0, @product.reload.available_stock
    2.times { order.with_lock { order.release!(:expired) } }
    assert_equal 1, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    assert_equal [ @small.id, @large.id ].sort, cart.reload.cart_items.pluck(:product_size_id).sort
    assert_equal [ 1, 1 ], cart.cart_items.pluck(:quantity)
  end

  test "stock cannot be borrowed from another size" do
    assert_raises(Checkout::Unavailable) { Checkout.reserve(sized_cart(quantity: 2)) }
    assert_equal 1, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    @small.update!(stock_quantity: 0)
    assert_raises(Checkout::Unavailable) { Checkout.reserve(sized_cart) }
    assert_equal 1, @large.reload.stock_quantity
  end

  test "even a forged database row cannot reserve a size from another product" do
    cart = sized_cart
    other = create_product
    foreign_size = other.product_sizes.create!(size_cm: 15)
    cart.cart_items.first.update_column(:product_size_id, foreign_size.id)
    assert_raises(Checkout::Unavailable) { Checkout.reserve(cart) }
    assert_equal 1, foreign_size.reload.stock_quantity
    assert_equal 0, Order.count
  end

  test "old unsized carts must choose a size after a product gains sizes" do
    plain = create_product
    cart = cart_for(plain)
    plain.product_sizes.create!(size_cm: 15)
    assert_raises(Checkout::Unavailable) { Checkout.reserve(cart) }
    assert_equal 1, plain.reload.available_stock
  end

  test "paid webhooks do not decrement size inventory again" do
    order = Checkout.reserve(sized_cart)
    event = stripe_event(order)
    2.times { StripeCheckoutEvent.call(event) }
    assert order.reload.paid?
    assert_equal 0, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
  end

  test "repeated expired webhooks restore the exact size once" do
    order = Checkout.reserve(sized_cart)
    2.times do
      StripeCheckoutEvent.call(stripe_event(order, type: "checkout.session.expired", status: "expired", payment_status: "unpaid"))
    end
    assert order.reload.expired?
    assert_equal 1, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    assert_equal @small, order.cart.cart_items.first.product_size
  end

  test "availability and sold visibility depend on size stock" do
    @product.update!(hide_when_sold: true)
    @small.update!(stock_quantity: 0)
    @large.update!(stock_quantity: 0)
    assert_equal 1, @product.reload.stock_quantity
    assert_equal 0, @product.available_stock
    assert_not @product.purchasable?
    assert_equal "Vendu", @product.stock_label
    assert_not_includes Product.in_stock, @product
    assert_not_includes Product.visible, @product
    @large.update!(stock_quantity: 1)
    assert @product.reload.purchasable?
    assert_includes Product.visible, @product
  end
  test "repeatable size stock can support quantities greater than one" do
    @small.update!(stock_quantity: 3)
    order = Checkout.reserve(sized_cart(quantity: 2))
    assert_equal 1, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    assert_equal 2, order.order_items.first.quantity
    assert_equal 1200, order.subtotal_cents
  end
end
