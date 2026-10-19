class Admin::ProductsController < Admin::BaseController
  before_action :set_product, only: [ :edit, :update, :destroy ]
  def index
    @products = paginate(Product.with_attached_photos.order(created_at: :desc))
  end
  def new
    @product = Product.new
  end
  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to admin_products_path, notice: "La création est publiée."
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit; end
  def update
    @product.with_lock do
      attributes = product_params
      if @product.order_items.joins(:order).where(orders: { status: "pending_payment" }).exists? && inventory_change?(attributes)
        @product.errors.add(:stock_quantity, "une réservation est en cours ; attendez sa confirmation ou son expiration avant d’ajuster le stock")
      else
        # Attachments append; removal and ordering only accept this product's IDs.
        new_photos = attributes.delete(:photos)
        @product.assign_attributes(attributes)
        @product.photos.attach(new_photos) if new_photos.present?
        @product.photo_order = Array(params.dig(:product, :photo_order)).map(&:to_s) & @product.photos.map { |photo| photo.id.to_s }
        if @product.save
          @product.photos_attachments.where(id: Array(params.dig(:product, :remove_photo_ids))).each(&:purge_later)
          return redirect_to admin_products_path, notice: "La création a été mise à jour."
        end
      end
    end
    render :edit, status: :unprocessable_entity
  end
  def destroy
    @product.with_lock { @product.update!(archived: true, active: false) }
    redirect_to admin_products_path, notice: "La création a été archivée.", status: :see_other
  end

  private
    def set_product
      @product = Product.find_by!(slug: params[:id])
    end
    def product_params
      params.require(:product).permit(:name, :description, :price_cents, :category, :stock_quantity, :unique_piece, :active, :archived, :hide_when_sold, photos: [])
    end
    def inventory_change?(attributes)
      %w[stock_quantity unique_piece].any? { |key| attributes.key?(key) && attributes[key].to_s != @product.public_send(key).to_s && !(key == "unique_piece" && ActiveModel::Type::Boolean.new.cast(attributes[key]) == @product.unique_piece) }
    end
end
