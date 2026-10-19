class Admin::DashboardController < Admin::BaseController
  def index
    @recent_orders = Order.order(created_at: :desc).limit(6)
    @product_count = Product.where(archived: false).count
    @paid_count = Order.paid.count
    @pending_count = Order.pending_payment.count
  end
end
