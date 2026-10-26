require "test_helper"

class CatalogueTest < ActionDispatch::IntegrationTest
  test "the atelier uses its actual name and all four categories" do
    get root_path
    assert_response :success
    assert_select ".brand", /les bijoux de titine/
    Product::CATEGORIES.each { |category| assert_select ".category-link", /#{Regexp.escape(category)}/ }
    assert_select 'img[src="/images/atelier-cerises.jpeg"]'
  end

  test "fruit collection can span categories and remains optional" do
    bracelet = create_product(name: "Bracelet fruits", collection: "Les fruits")
    ring = create_product(name: "Bague fruits", category: "Bagues", collection: "Les fruits")
    ordinary = create_product(name: "Bracelet hors collection")
    get products_path(collection: "Les fruits")
    assert_response :success
    assert_select ".product-card", count: 2
    assert_select ".product-card h3", bracelet.name
    assert_select ".product-card h3", ring.name
    assert_select ".product-card h3", text: ordinary.name, count: 0
    assert_select 'input[name="collection"][value="Les fruits"]'
    get products_path(category: "Bagues", collection: "Les fruits")
    assert_select ".product-card", count: 1
    assert_select ".product-card h3", ring.name
    get product_path(ring)
    assert_select ".product-description .collection-label", "Collection les fruits"
    assert_nil ordinary.collection
  end

  test "pagination retains the collection filter" do
    25.times { |i| create_product(name: "Fruit #{i}", collection: "Les fruits", category: "Bagues") }
    get products_path(category: "Bagues", collection: "Les fruits")
    assert_select ".product-card", count: 24
    assert_select ".pagination a", text: "Suivant →" do |links|
      query = URI.decode_www_form(URI(links.first["href"]).query).to_h
      assert_equal "Les fruits", query["collection"]
      assert_equal "Bagues", query["category"]
      assert_equal "2", query["page"]
    end
    get products_path(category: "Bagues", collection: "Les fruits", page: 2)
    assert_select ".product-card", count: 1
  end

  test "admin can keep an unpriced draft and publish after setting price and collection" do
    sign_in_as(users(:one))
    post admin_products_path, params: { product: { name: "Création à préparer", description: "Création faite main", category: "Porte-clés", price_cents: "", active: "0" } }
    assert_redirected_to admin_products_path
    product = Product.last
    assert_nil product.price_cents
    assert_not product.active?
    get admin_products_path
    assert_select ".admin-table", /Prix à renseigner/
    patch admin_product_path(product), params: { product: { active: "1" } }
    assert_response :unprocessable_entity
    assert_not product.reload.active?
    patch admin_product_path(product), params: { product: { price_cents: 1200, collection: "Les fruits", active: "1" } }
    assert_redirected_to admin_products_path
    assert product.reload.active?
    assert_equal "Les fruits", product.collection
  end
  test "unpublished collections are not advertised and direct links explain the state" do
    create_product(collection: "Les fruits", active: false)
    get root_path
    assert_select ".collection-section", count: 0
    get products_path
    assert_select ".collection-filters", count: 0
    get "/boutique?collection=Les+fruits"
    assert_response :success
    assert_select "h1", "Les fruits."
    assert_select ".empty-state h2", "Cette collection est en préparation."
    assert_select ".product-card", count: 0
  end

  test "the collection is advertised automatically once a member is published" do
    create_product(collection: "Les fruits")
    get root_path
    assert_select ".collection-section a", text: /Découvrir la collection/
    get "/boutique?collection=Les+fruits"
    assert_response :success
    assert_select ".product-card", count: 1
    assert_select ".collection-filters a.selected", "Les fruits"
  end
  test "the imported fruit catalogue is visible at the public collection URL" do
    CatalogImport.call
    get "/boutique?collection=Les+fruits"
    assert_response :success
    assert_select ".product-card", count: 6
    assert_select ".product-card .collection-label", text: "Les fruits", count: 6
    assert_select ".product-card .price", text: /6,00.*€/m, count: 6
    assert_select ".empty-state", count: 0
    fruit = Product.find_by!(catalog_reference: "titine-fruits-00008")
    get product_path(fruit)
    assert_response :success
    assert_select ".photo-thumbnails button", count: 2
    assert_select ".product-description .collection-label", "Collection les fruits"
    get root_path
    assert_select ".collection-section a", text: /Découvrir la collection/
  end
  test "rings cost three euros through checkout and only non-fruit items show one size" do
    CatalogImport.call
    get products_path(category: "Bagues")
    assert_response :success
    assert_select ".product-card", count: 5
    assert_select ".product-card .price", text: /3,00.*€/m, count: 5
    assert_select ".product-card .product-size-label", text: "Taille unique", count: 5
    ring = Product.find_by!(catalog_reference: "titine-9351")
    get product_path(ring)
    assert_select ".product-description .product-size-label", "Taille unique"
    assert_select 'select[name="product_size_id"]', count: 0
    post cart_items_path, params: { product_id: ring.id, quantity: 1, price_cents: 1 }
    get cart_path
    assert_select ".cart-item .product-size-label", "Taille unique"
    Stripe::Checkout::Session.stub(:create, ->(parameters, *) {
      assert_equal 300, parameters[:line_items].first[:price_data][:unit_amount]
      stripe_session(Order.last, status: "open", payment_status: "unpaid")
    }) { post checkout_cart_path }
    assert_redirected_to "https://checkout.stripe.com/c/test"
    assert_equal 300, Order.last.order_items.first.unit_price_cents
    assert_equal 500, Order.last.total_cents
    get products_path(collection: "Les fruits")
    assert_select ".product-card", count: 6
    assert_select ".product-size-label", count: 0
    get product_path(Product.find_by!(catalog_reference: "titine-fruits-00006"))
    assert_select ".product-description .product-size-label", count: 0
    assert_select 'select[name="product_size_id"]'
    get products_path(category: "Porte-clés")
    assert_select ".product-card .product-size-label", text: "Taille unique", count: 7
  end
end
