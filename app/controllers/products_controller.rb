class ProductsController < ApplicationController
  allow_unauthenticated_access
  def index
    @products = Product.visible.with_attached_photos.newest
    @products = @products.where(category: params[:category]) if Product::CATEGORIES.include?(params[:category])
    @products = @products.where("name ILIKE ?", "%#{Product.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @products = @products.where("stock_quantity > 0") if params[:available] == "1"
    @products = paginate(@products)
  end
  def show
    @product = Product.visible.with_attached_photos.find_by!(slug: params[:slug])
    @related = Product.visible.with_attached_photos.where.not(id: @product.id).where(category: @product.category).limit(3)
  end
end
