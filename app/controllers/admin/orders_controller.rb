class Admin::OrdersController < Admin::BaseController
  def index
    @orders = paginate(Order.order(created_at: :desc))
  end
  def show
    @order = Order.includes(:order_items).find_by!(public_token: params[:id])
  end
end
