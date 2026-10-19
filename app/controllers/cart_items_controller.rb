class CartItemsController < ApplicationController
  allow_unauthenticated_access
  def create
    change_item do
      product = Product.visible.find(params[:product_id])
      item = current_cart.cart_items.find_or_initialize_by(product: product)
      item.quantity = (item.persisted? ? item.quantity : 0) + quantity
      validate_stock!(item)
      item.save!
    end
  end
  def update
    change_item do
      item = current_cart.cart_items.find(params[:id])
      item.quantity = quantity
      validate_stock!(item)
      item.save!
    end
  end
  def destroy
    change_item { current_cart.cart_items.find(params[:id]).destroy! }
  end

  private
    def quantity
      Integer(params.fetch(:quantity, 1).to_s, 10)
    end
    def validate_stock!(item)
      unless item.product.purchasable? && item.quantity.between?(1, [ item.product.stock_quantity, 99 ].min) && (!item.product.unique_piece? || item.quantity == 1)
        raise Checkout::Unavailable, "Désolé, cette pièce vient d’être vendue ou la quantité demandée n’est plus disponible."
      end
    end
    def change_item
      current_cart.with_lock { yield }
      redirect_to cart_path, notice: "Votre panier a été mis à jour.", status: :see_other
    rescue Checkout::Unavailable => error
      redirect_to cart_path, alert: error.message, status: :see_other
    rescue ArgumentError, ActiveRecord::RecordInvalid
      redirect_to cart_path, alert: "Veuillez choisir une quantité disponible.", status: :see_other
    end
end
