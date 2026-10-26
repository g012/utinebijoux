require "test_helper"

class ProductSizesTest < ActionDispatch::IntegrationTest
  setup do
    @product = create_product(name: "Bracelet cerises", price_cents: 600, unique_piece: false)
    @small = @product.product_sizes.create!(size_cm: 15)
    @large = @product.product_sizes.create!(size_cm: 18)
    @extra = @product.product_sizes.create!(size_cm: 20, stock_quantity: 0)
  end

  test "size selector identifies unavailable sizes and requires a choice" do
    get product_path(@product)
    assert_response :success
    assert_select 'select[name="product_size_id"][required]'
    assert_select "option[value=?]", @small.id.to_s, "15 cm"
    assert_select "option[value=?][disabled]", @extra.id.to_s, "20 cm — épuisé"
    post cart_items_path, params: { product_id: @product.id, quantity: 1 }
    assert_redirected_to cart_path
    assert_equal 0, CartItem.count
    follow_redirect!
    assert_select ".flash.alert", /Choisissez une taille/
  end

  test "different sizes stay distinct and cannot be substituted with forged ids or prices" do
    other = create_product
    foreign_size = other.product_sizes.create!(size_cm: 15)
    post cart_items_path, params: { product_id: @product.id, product_size_id: foreign_size.id, quantity: 1 }
    assert_equal 0, CartItem.count
    [ @small, @large ].each do |size|
      post cart_items_path, params: { product_id: @product.id, product_size_id: size.id, quantity: 1, price_cents: 1 }
      assert_redirected_to cart_path
    end
    assert_equal 2, CartItem.count
    get cart_path
    assert_select ".cart-item h2", "Bracelet cerises — 15 cm"
    assert_select ".cart-item h2", "Bracelet cerises — 18 cm"
    post cart_items_path, params: { product_id: @product.id, product_size_id: @small.id, quantity: 1 }
    assert_equal [ 1, 1 ], CartItem.order(:id).pluck(:quantity)
    Stripe::Checkout::Session.stub(:create, ->(parameters, *) {
      assert_equal [ 600, 600 ], parameters[:line_items].map { |item| item[:price_data][:unit_amount] }
      assert_equal [ "Bracelet cerises — 15 cm", "Bracelet cerises — 18 cm" ], parameters[:line_items].map { |item| item[:price_data][:product_data][:name] }
      stripe_session(Order.last, status: "open", payment_status: "unpaid")
    }) { post checkout_cart_path }
    assert_redirected_to "https://checkout.stripe.com/c/test"
    assert_equal [ 15, 18 ], Order.last.order_items.order(:size_cm).pluck(:size_cm)
  end

  test "availability filtering does not use the generic stock for sized bracelets" do
    @small.update!(stock_quantity: 0)
    @large.update!(stock_quantity: 0)
    get products_path(available: "1")
    assert_select ".product-card h3", text: @product.name, count: 0
  end

  test "admin can adjust a size and add another without resetting other sizes" do
    sign_in_as(users(:one))
    patch admin_product_path(@product), params: { product: { product_sizes_attributes: {
      "0" => { id: @small.id, size_cm: 15, stock_quantity: 0 },
      "1" => { size_cm: 22, stock_quantity: 1 }
    } } }
    assert_redirected_to admin_products_path
    assert_equal 0, @small.reload.stock_quantity
    assert_equal 1, @large.reload.stock_quantity
    assert_equal 1, @product.product_sizes.find_by!(size_cm: 22).stock_quantity
    get edit_admin_product_path(@product)
    assert_response :success
    assert_select 'input[name="product[stock_quantity]"][disabled]'
    assert_select 'input[name*="product_sizes_attributes"][value="22"]'
  end

  test "pending reservations prevent admin changes to size inventory" do
    sign_in_as(users(:one))
    cart = Cart.create!
    cart.cart_items.create!(product: @product, product_size: @small)
    order = Checkout.reserve(cart)
    patch admin_product_path(@product), params: { product: { product_sizes_attributes: {
      "0" => { id: @small.id, stock_quantity: 1 }
    } } }
    assert_response :unprocessable_entity
    assert_equal 0, @small.reload.stock_quantity
    patch admin_product_path(@product), params: { product: { description: "Description modifiée", product_sizes_attributes: {
      "0" => { id: @small.id, size_cm: 15, stock_quantity: 0 }
    } } }
    assert_redirected_to admin_products_path
    order.with_lock { order.release!(:expired) }
    assert_equal 1, @small.reload.stock_quantity
  end
end
