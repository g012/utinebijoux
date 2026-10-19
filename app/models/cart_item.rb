class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 99 }
  validates :product_id, uniqueness: { scope: :cart_id }
end
