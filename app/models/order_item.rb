class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product
  belongs_to :product_size, optional: true
  attr_readonly :order_id, :product_id, :product_name, :unit_price_cents, :quantity, :product_size_id, :size_cm
  validates :quantity, :unit_price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :product_name, presence: true
  validates :size_cm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :size_cm, presence: true, if: -> { product_size_id.present? }
  def total_cents = unit_price_cents * quantity
  def display_name = size_cm ? "#{product_name} — #{size_cm} cm" : product_name
end
