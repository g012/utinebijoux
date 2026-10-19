class Cart < ApplicationRecord
  has_secure_token
  has_many :cart_items, dependent: :destroy
  has_many :orders, dependent: :restrict_with_exception
  def pending_order = orders.find_by(status: "pending_payment")
  def count = cart_items.sum(:quantity)
  def subtotal_cents = cart_items.includes(:product).sum { |item| item.quantity * item.product.price_cents }
end
