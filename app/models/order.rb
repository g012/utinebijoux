class Order < ApplicationRecord
  belongs_to :cart
  has_many :order_items, dependent: :restrict_with_exception
  has_secure_token :public_token, length: 32
  enum :status, { pending_payment: "pending_payment", paid: "paid", expired: "expired", cancelled: "cancelled", refunded: "refunded" }, validate: true
  after_update_commit :enqueue_confirmation, if: -> { saved_change_to_status? && paid? }
  before_validation :assign_number, on: :create
  attr_readonly :subtotal_cents, :shipping_cents, :total_cents, :currency, :checkout_request
  scope :awaiting_cleanup, -> { pending_payment.where(expires_at: ..Time.current) }
  def to_param = public_token
  def status_label
    { "pending_payment" => "En attente", "paid" => "Payée", "expired" => "Expirée", "cancelled" => "Annulée", "refunded" => "Remboursée" }.fetch(status)
  end

  # Call while holding the order lock. Reserving already removed these units.
  def release!(new_status)
    return unless pending_payment?
    products = Product.where(id: order_items.select(:product_id)).order(:id).lock.index_by(&:id)
    sizes = ProductSize.where(id: order_items.select(:product_size_id)).order(:id).lock.index_by(&:id)
    order_items.each do |item|
      inventory = item.product_size_id ? sizes.fetch(item.product_size_id) : products.fetch(item.product_id)
      inventory.update!(stock_quantity: inventory.stock_quantity + item.quantity)
    end
    # Keep the selection available for a fresh checkout, without reserving it.
    cart.with_lock do
      order_items.each do |item|
        cart_item = cart.cart_items.find_or_initialize_by(product_id: item.product_id, product_size_id: item.product_size_id)
        cart_item.quantity = [ (cart_item.persisted? ? cart_item.quantity : 0) + item.quantity, 99 ].min
        cart_item.save!
      end
    end
    update!(status: new_status, released_at: Time.current)
  end

  private
    def enqueue_confirmation
      SendOrderConfirmationJob.perform_later(self)
    rescue StandardError => error
      Rails.logger.error("Confirmation enqueue failed for #{number}: #{error.class}")
      Rails.error.report(error, context: { order_number: number })
    end
    def assign_number
      self.number ||= "AT-#{Time.current.strftime('%y%m%d')}-#{SecureRandom.hex(4).upcase}"
    end
end
