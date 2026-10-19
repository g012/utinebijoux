require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "new products default to one available unique piece in euros" do
    product = create_product
    assert_equal 1, product.stock_quantity
    assert product.unique_piece?
    assert_equal "eur", product.currency
    assert_equal "Pièce unique", product.stock_label
  end

  test "one remaining repeatable item has a distinct label" do
    assert_equal "Dernier exemplaire", create_product(unique_piece: false).stock_label
  end

  test "sold pieces remain visible by default but cannot be purchased" do
    product = create_product(stock_quantity: 0)
    assert_includes Product.visible, product
    assert_not product.purchasable?
    assert_equal "Vendu", product.stock_label
    product.update!(hide_when_sold: true)
    assert_not_includes Product.visible, product
  end

  test "archived and inactive pieces are hidden" do
    assert_not_includes Product.visible, create_product(archived: true)
    assert_not_includes Product.visible, create_product(active: false)
  end

  test "unique products cannot have more than one available copy" do
    assert_not Product.new(name: "Perles", description: "Bijou", price_cents: 2000, stock_quantity: 2).valid?
    assert create_product(unique_piece: false, stock_quantity: 4).purchasable?
  end

  test "product edits preserve its stable slug" do
    product = create_product
    slug = product.slug
    product.update!(name: "Nouveau nom")
    assert_equal slug, product.reload.slug
  end

  test "database rejects negative stock even bypassing validations" do
    product = create_product
    assert_raises(ActiveRecord::StatementInvalid) { product.update_column(:stock_quantity, -1) }
  end
end
