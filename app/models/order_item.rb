class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product
  attr_readonly :order_id, :product_id, :product_name, :unit_price_cents, :quantity
  validates :quantity, :unit_price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :product_name, presence: true
  def total_cents = unit_price_cents * quantity
end
