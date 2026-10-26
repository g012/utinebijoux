class AddProductSizes < ActiveRecord::Migration[8.1]
  def change
    create_table :product_sizes do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :size_cm, null: false
      t.integer :stock_quantity, null: false, default: 1
      t.timestamps
    end
    add_index :product_sizes, [ :product_id, :size_cm ], unique: true
    add_check_constraint :product_sizes, "size_cm > 0 AND stock_quantity >= 0", name: "valid_size_inventory"

    add_reference :cart_items, :product_size, foreign_key: true
    remove_index :cart_items, [ :cart_id, :product_id ]
    add_index :cart_items, [ :cart_id, :product_id ], unique: true, where: "product_size_id IS NULL", name: "unique_unsized_cart_item"
    add_index :cart_items, [ :cart_id, :product_size_id ], unique: true, where: "product_size_id IS NOT NULL", name: "unique_sized_cart_item"

    add_reference :order_items, :product_size, foreign_key: true
    add_column :order_items, :size_cm, :integer
    add_check_constraint :order_items, "(product_size_id IS NULL AND size_cm IS NULL) OR (product_size_id IS NOT NULL AND size_cm IS NOT NULL AND size_cm > 0)", name: "consistent_order_size"
  end
end
