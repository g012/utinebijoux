require "test_helper"

class CatalogImportTest < ActiveSupport::TestCase
  test "the catalogue pairs 77 originals into 42 published creations and imports idempotently" do
    products = CatalogImport.call
    assert_equal 42, products.size
    assert_equal({ "Bracelets en fil" => 5, "Bracelets en perles" => 25, "Bagues" => 5, "Porte-clés" => 7 }, products.group_by(&:category).transform_values(&:size))
    products.each do |product|
      assert product.active?
      assert_equal(product.category == "Bagues" ? 300 : 600, product.price_cents)
      expected_sizes = product.collection == "Les fruits" ? (product.catalog_reference.in?(%w[titine-fruits-00006 titine-fruits-00009]) ? [ 15, 18, 20 ] : [ 15, 18 ]) : []
      assert_equal expected_sizes, product.product_sizes.map(&:size_cm).sort
      assert_equal [ expected_sizes.size, 1 ].max, product.available_stock
      assert_equal(product.category == "Porte-clés" ? 1 : 2, product.photos.size)
      product.photos.each do |photo|
        assert photo.blob.service.exist?(photo.blob.key), "Missing upload: #{photo.filename}"
        assert_equal File.binread(Rails.root.join("db/catalogue/photos", photo.filename.to_s)), photo.blob.download
      end
    end
    assert_equal 77, products.sum { |product| product.photos.size }
    assert_equal 6, products.count { |item| item.collection == "Les fruits" }
    assert_equal 36, products.count { |item| item.collection.nil? }
    expected_fruit_pairs = {
      "titine-fruits-00006" => %w[image00006.jpeg image00007.jpeg],
      "titine-fruits-00008" => %w[image00008.jpeg image00011.jpeg],
      "titine-fruits-00009" => %w[image00009.jpeg image00010.jpeg],
      "titine-fruits-00012" => %w[image00012.jpeg image00013.jpeg],
      "titine-fruits-00014" => %w[image00014.jpeg image00016.jpeg],
      "titine-fruits-00015" => %w[image00015.jpeg image00017.jpeg]
    }
    products.select { |item| item.collection == "Les fruits" }.each do |item|
      assert_equal "Bracelets en perles", item.category
      assert_equal expected_fruit_pairs.fetch(item.catalog_reference), item.photos.map { |photo| photo.filename.to_s }.sort
    end
    product = products.first
    product.update!(name: "Nom choisi par Titine", price_cents: 1800, stock_quantity: 0, collection: "Les fruits", active: true)
    ids = product.photos.map(&:id).reverse.map(&:to_s)
    product.update!(photo_order: ids)
    assert_no_difference [ "Product.count", "ProductSize.count", "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      CatalogImport.call
    end
    product.reload
    assert_equal "Nom choisi par Titine", product.name
    assert_equal 1800, product.price_cents
    assert_equal 0, product.stock_quantity
    assert_equal "Les fruits", product.collection
    assert product.active?
    assert_equal ids, product.ordered_photos.map { |photo| photo.id.to_s }
    # A process stopped after database commit must not leave a permanently broken photo.
    photo = product.photos.first
    photo.blob.service.delete(photo.blob.key)
    assert_not photo.blob.service.exist?(photo.blob.key)
    CatalogImport.call
    assert photo.blob.service.exist?(photo.blob.key)
  end
  test "reimporting never restocks a reserved size" do
    CatalogImport.call
    product = Product.find_by!(catalog_reference: "titine-fruits-00006")
    size = product.product_sizes.find_by!(size_cm: 15)
    cart = Cart.create!
    cart.cart_items.create!(product: product, product_size: size)
    Checkout.reserve(cart)
    assert_no_difference "ProductSize.count" do
      CatalogImport.call
    end
    assert_equal 0, size.reload.stock_quantity
    assert_equal [ 18, 20 ], product.reload.product_sizes.select { |item| item.stock_quantity.positive? }.map(&:size_cm).sort
  end
end
