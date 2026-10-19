class CartsController < ApplicationController
  allow_unauthenticated_access
  def show
    @items = current_cart.cart_items.includes(product: { photos_attachments: :blob })
    @pending_order = current_cart.pending_order
  end
  def checkout
    order = Checkout.start(current_cart)
    if order.pending_payment? && order.checkout_url.present? && order.expires_at.future?
      redirect_to order.checkout_url, allow_other_host: true, status: :see_other
    else
      redirect_to cart_path, alert: "Cette session est terminée. Vous pouvez choisir à nouveau vos créations.", status: :see_other
    end
  rescue Checkout::Unavailable => error
    redirect_to cart_path, alert: error.message, status: :see_other
  rescue Checkout::NotConfigured
    redirect_to cart_path, alert: "Le paiement est momentanément indisponible. Écrivez-nous pour nous contacter.", status: :see_other
  rescue Stripe::StripeError => error
    Rails.error.report(error)
    redirect_to cart_path, alert: "La connexion au paiement a été interrompue. Réessayez : votre réservation est conservée si nécessaire.", status: :see_other
  end
  def cancel_checkout
    order = current_cart.pending_order
    ReconcileCheckout.call(order, cancel: true) if order
    redirect_to cart_path, notice: "La session de paiement a été vérifiée. Les pièces non payées sont à nouveau disponibles.", status: :see_other
  rescue Stripe::StripeError => error
    Rails.error.report(error)
    redirect_to cart_path, alert: "La réservation reste active pendant la vérification du paiement. Réessayez dans un instant.", status: :see_other
  end
end
