class CreateShop < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description, null: false, default: ""
      t.integer :price_cents, null: false
      t.string :currency, null: false, default: "eur"
      t.integer :stock_quantity, null: false, default: 1
      t.boolean :unique_piece, null: false, default: true
      t.boolean :active, null: false, default: true
      t.boolean :archived, null: false, default: false
      t.boolean :hide_when_sold, null: false, default: false
      t.string :category, null: false, default: "Bracelets"
      t.jsonb :photo_order, null: false, default: []
      t.timestamps
    end
    add_index :products, :slug, unique: true
    add_check_constraint :products, "stock_quantity >= 0", name: "positive_stock"
    add_check_constraint :products, "price_cents > 0", name: "positive_price"
    add_check_constraint :products, "currency = 'eur'", name: "product_eur"
    add_check_constraint :products, "NOT unique_piece OR stock_quantity <= 1", name: "unique_stock"

    create_table :carts do |t|
      t.string :token, null: false
      t.timestamps
    end
    add_index :carts, :token, unique: true
    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :cart_items, [ :cart_id, :product_id ], unique: true
    add_check_constraint :cart_items, "quantity > 0 AND quantity <= 99", name: "cart_quantity"

    create_table :orders do |t|
      t.references :cart, null: false, foreign_key: true
      t.string :number, null: false
      t.string :public_token, null: false
      t.string :status, null: false, default: "pending_payment"
      t.string :currency, null: false, default: "eur"
      t.integer :subtotal_cents, null: false
      t.integer :shipping_cents, null: false
      t.integer :total_cents, null: false
      t.datetime :expires_at, null: false
      t.datetime :paid_at
      t.datetime :released_at
      t.datetime :confirmation_enqueued_at
      t.string :stripe_session_id
      t.string :stripe_payment_intent_id
      t.string :stripe_customer_id
      t.jsonb :checkout_request, null: false, default: {}
      t.string :checkout_url
      t.string :customer_email
      t.string :customer_name
      t.jsonb :customer_details, null: false, default: {}
      t.jsonb :shipping_details, null: false, default: {}
      t.timestamps
    end
    add_index :orders, :number, unique: true
    add_index :orders, :public_token, unique: true
    add_index :orders, :stripe_session_id, unique: true
    add_index :orders, :stripe_payment_intent_id, unique: true
    add_index :orders, :cart_id, unique: true, where: "status = 'pending_payment'", name: "one_pending_order_per_cart"
    add_index :orders, [ :status, :expires_at ]
    add_check_constraint :orders, "status IN ('pending_payment', 'paid', 'expired', 'cancelled', 'refunded')", name: "order_status"
    add_check_constraint :orders, "subtotal_cents > 0 AND shipping_cents >= 0 AND total_cents = subtotal_cents + shipping_cents", name: "order_totals"

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :product_name, null: false
      t.integer :unit_price_cents, null: false
      t.integer :quantity, null: false
      t.timestamps
    end
    add_check_constraint :order_items, "quantity > 0 AND unit_price_cents > 0", name: "order_item_values"
    create_table :stripe_events do |t|
      t.string :stripe_id, null: false
      t.string :event_type, null: false
      t.timestamps
    end
    add_index :stripe_events, :stripe_id, unique: true
  end
end
