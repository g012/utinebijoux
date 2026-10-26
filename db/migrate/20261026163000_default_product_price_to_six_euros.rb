class DefaultProductPriceToSixEuros < ActiveRecord::Migration[8.1]
  def change
    change_column_default :products, :price_cents, from: nil, to: 600
  end
end
