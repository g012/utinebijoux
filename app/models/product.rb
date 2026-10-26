class Product < ApplicationRecord
  CATEGORIES = [ "Bracelets en perles", "Bracelets en fil", "Bagues", "Porte-clés" ].freeze
  COLLECTIONS = [ "Les fruits" ].freeze
  has_many_attached :photos
  has_many :product_sizes, dependent: :restrict_with_error
  accepts_nested_attributes_for :product_sizes, reject_if: ->(attributes) { attributes["id"].blank? && attributes["size_cm"].blank? }
  has_many :order_items, dependent: :restrict_with_error
  has_many :cart_items, dependent: :destroy
  before_validation :assign_slug, on: :create
  normalizes :currency, with: ->(value) { value.downcase }
  normalizes :collection, with: ->(value) { value.presence }
  validates :name, :slug, :description, presence: true
  validates :name, length: { maximum: 180 }
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :price_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :price_cents, presence: true, if: :active?
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: [ "eur" ] }
  validates :category, inclusion: { in: CATEGORIES }
  validates :collection, inclusion: { in: COLLECTIONS }, allow_nil: true
  validate :unique_stock
  validate :acceptable_photos
  IN_STOCK_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM product_sizes WHERE product_sizes.product_id = products.id AND product_sizes.stock_quantity > 0)
    OR (NOT EXISTS (SELECT 1 FROM product_sizes WHERE product_sizes.product_id = products.id) AND products.stock_quantity > 0)
  SQL
  scope :in_stock, -> { where(IN_STOCK_SQL) }
  scope :visible, -> { where(active: true, archived: false).where("NOT hide_when_sold OR (#{IN_STOCK_SQL})") }
  scope :newest, -> { order(created_at: :desc) }

  def to_param = slug
  def one_size? = collection != "Les fruits"
  def sized? = product_sizes.any? { |size| size.size_cm.present? }
  def available_stock = sized? ? product_sizes.sum(&:stock_quantity) : stock_quantity
  def purchasable? = active? && !archived? && available_stock.positive?
  def ordered_photos
    photos.sort_by { |photo| photo_order.index(photo.id.to_s) || photo_order.length + photo.id }
  end
  def stock_label
    return "Vendu" if available_stock.zero?
    return "Pièce unique" if unique_piece? && !sized?
    return "Dernier exemplaire" if available_stock == 1
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
