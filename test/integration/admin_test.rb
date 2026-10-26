require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  test "all admin pages require Rails authentication" do
    [ admin_root_path, admin_products_path, new_admin_product_path, admin_orders_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { name: "Malicious", description: "Test", price_cents: 1000 } }
    end
    assert_redirected_to new_session_path
    get "/users/new"
    assert_response :not_found
  end

  test "authenticated admin can publish with stock one and manage orders" do
    sign_in_as(users(:one))
    get admin_root_path
    assert_response :success
    get new_admin_product_path
    assert_response :success
    post admin_products_path, params: { product: { name: "Perle du matin", description: "Création en perles", price_cents: 2500, category: "Bracelets en perles", active: "1" } }
    assert_redirected_to admin_products_path
    product = Product.last
    assert_equal 1, product.stock_quantity
    assert product.unique_piece?
    get edit_admin_product_path(product)
    assert_response :success
    order = reserve(product)
    get admin_order_path(order)
    assert_response :success
    get admin_orders_path
    assert_response :success
  end

  test "stock cannot be recreated by admin while a reservation exists" do
    sign_in_as(users(:one))
    product = create_product
    order = reserve(product)
    patch admin_product_path(product), params: { product: { stock_quantity: 1 } }
    assert_response :unprocessable_entity
    assert_equal 0, product.reload.stock_quantity
    order.with_lock { order.release!(:expired) }
    patch admin_product_path(product), params: { product: { stock_quantity: 0, hide_when_sold: "1" } }
    assert_redirected_to admin_products_path
    assert_not_includes Product.visible, product.reload
  end

  test "archiving removes a creation while preserving purchase snapshots" do
    sign_in_as(users(:one))
    order = reserve
    product = order.order_items.first.product
    delete admin_product_path(product)
    assert product.reload.archived?
    assert_equal "Bracelet Aurore", order.order_items.first.product_name
    assert_not_includes Product.visible, product
  end
  test "admin can append and reorder photos without removing another product's image" do
    sign_in_as(users(:one))
    product = create_product
    other = create_product(name: "Autre création")
    [ product, other ].each do |record|
      record.photos.attach(io: File.open(Rails.root.join("public/images/bracelet.jpg")), filename: "bracelet.jpg", content_type: "image/jpeg")
    end
    first_id = product.photos.first.id
    other_photo = other.photos.first
    upload = Rack::Test::UploadedFile.new(Rails.root.join("public/images/pearls.jpg"), "image/jpeg")
    patch admin_product_path(product), params: { product: { photos: [ upload ], photo_order: [ first_id ], remove_photo_ids: [ other_photo.id ] } }
    assert_redirected_to admin_products_path
    assert_equal 2, product.reload.photos.count
    assert ActiveStorage::Attachment.exists?(other_photo.id)
    ids = product.photos.map(&:id).reverse
    patch admin_product_path(product), params: { product: { photo_order: ids } }
    assert_redirected_to admin_products_path
    assert_equal ids, product.reload.ordered_photos.map(&:id)
    assert_enqueued_with(job: ActiveStorage::PurgeJob) do
      patch admin_product_path(product), params: { product: { remove_photo_ids: [ first_id ], photo_order: ids } }
    end
    assert_equal 1, product.reload.photos.count
  end
end
