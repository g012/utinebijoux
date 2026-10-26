class UpdateAtelierCatalogue < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :collection, :string
    add_column :products, :catalog_reference, :string
    add_index :products, :catalog_reference, unique: true
    add_index :products, :collection
    change_column_default :products, :category, from: "Bracelets", to: "Bracelets en perles"
    execute "UPDATE products SET category = 'Bracelets en perles' WHERE category IN ('Bracelets', 'Colliers', 'Boucles', 'Autres')"
    change_column_null :products, :price_cents, true
    add_check_constraint :products, "NOT active OR price_cents IS NOT NULL", name: "published_product_price"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Les catégories d’origine ne peuvent pas être reconstituées."
  end
end
