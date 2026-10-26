class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :product
  belongs_to :product_size, optional: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 99 }
  validates :product_id, uniqueness: { scope: :cart_id, conditions: -> { where(product_size_id: nil) } }, if: -> { product_size_id.nil? }
  validates :product_size_id, uniqueness: { scope: :cart_id }, allow_nil: true
  validate :matching_size

  def display_name = product_size ? "#{product.name} — #{product_size.label}" : product.name
  def available_quantity = product_size ? product_size.stock_quantity : product.stock_quantity
  def max_quantity = [ available_quantity, 99, product.unique_piece? && !product.sized? ? 1 : 99 ].min
  def purchasable?
    product.purchasable? && product.sized? == product_size.present? &&
      (!product_size || product_size.product_id == product_id) && available_quantity.positive?
  end

  private
    def matching_size
      if product && (product.sized? != product_size.present? || (product_size && product_size.product_id != product_id))
        errors.add(:product_size, "choisissez une taille disponible pour cette création")
      end
    end
end
