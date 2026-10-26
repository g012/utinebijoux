class ProductSize < ApplicationRecord
  belongs_to :product
  has_many :cart_items, dependent: :restrict_with_error
  has_many :order_items, dependent: :restrict_with_error
  attr_readonly :product_id
  validates :size_cm, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :product_id }
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :stable_size

  def label = "#{size_cm} cm"

  private
    def stable_size
      errors.add(:size_cm, "ne peut pas être modifiée ; ajoutez une autre taille") if persisted? && will_save_change_to_size_cm?
    end
end
