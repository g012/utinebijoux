class ProductsController < ApplicationController
  allow_unauthenticated_access
  def index
    @collections = Product.visible.where(collection: Product::COLLECTIONS).distinct.pluck(:collection)
    @collection = params[:collection].presence_in(Product::COLLECTIONS)
    @products = Product.visible.with_attached_photos.includes(:product_sizes).newest
    @products = @products.where(category: params[:category]) if Product::CATEGORIES.include?(params[:category])
    @products = @products.where(collection: @collection) if @collection
    @products = @products.where("name ILIKE ?", "%#{Product.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @products = @products.in_stock if params[:available] == "1"
    @products = paginate(@products)
  end
  def show
    @product = Product.visible.with_attached_photos.includes(:product_sizes).find_by!(slug: params[:slug])
    @related = Product.visible.with_attached_photos.includes(:product_sizes).where.not(id: @product.id).where(category: @product.category).limit(3)
  end
end
