class Product < ApplicationRecord
  CATEGORIES = %w[Bracelets Colliers Boucles Autres].freeze
  has_many_attached :photos
  has_many :order_items, dependent: :restrict_with_error
  has_many :cart_items, dependent: :destroy
  before_validation :assign_slug, on: :create
  normalizes :currency, with: ->(value) { value.downcase }
  validates :name, :slug, :description, presence: true
  validates :name, length: { maximum: 180 }
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :price_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: [ "eur" ] }
  validates :category, inclusion: { in: CATEGORIES }
  validate :unique_stock
  validate :acceptable_photos
  scope :visible, -> { where(active: true, archived: false).where("NOT hide_when_sold OR stock_quantity > 0") }
  scope :newest, -> { order(created_at: :desc) }

  def to_param = slug
  def purchasable? = active? && !archived? && stock_quantity.positive?
  def ordered_photos
    photos.sort_by { |photo| photo_order.index(photo.id.to_s) || photo_order.length + photo.id }
  end
  def stock_label
    return "Vendu" if stock_quantity.zero?
    return "Pièce unique" if unique_piece?
    return "Dernier exemplaire" if stock_quantity == 1
    "Petite série"
  end

  private
    def assign_slug
      self.slug ||= "#{name.to_s.parameterize}-#{SecureRandom.hex(3)}"
    end
    def unique_stock
      errors.add(:stock_quantity, "doit être au maximum de 1 pour une pièce unique") if unique_piece? && stock_quantity.to_i > 1
    end
    def acceptable_photos
      errors.add(:photos, "10 photos maximum") if photos.size > 10
      photos.each do |photo|
        errors.add(:photos, "utilisez JPEG, PNG ou WebP (10 Mo maximum)") unless photo.blob.content_type.in?(%w[image/jpeg image/png image/webp]) && photo.blob.byte_size <= 10.megabytes
      end
    end
end
