class OrdersController < ApplicationController
  allow_unauthenticated_access
  def show
    # Random capability URL; no sequential IDs or customer details are exposed.
    @order = Order.includes(:order_items).find_by!(public_token: params[:token])
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
