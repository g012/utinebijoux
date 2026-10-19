class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern
  stale_when_importmap_changes
  helper_method :current_cart

  private
    def paginate(scope, per_page: 24)
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / per_page).ceil, 1 ].max
      @page = params[:page].to_i.clamp(1, @total_pages)
      scope.offset((@page - 1) * per_page).limit(per_page)
    end

    def current_cart
      @current_cart ||= begin
        cart = Cart.find_by(token: cookies.signed[:cart_token]) if cookies.signed[:cart_token].present?
        cart ||= Cart.create!
        cookies.signed[:cart_token] = { value: cart.token, expires: 30.days.from_now, httponly: true, same_site: :lax, secure: Rails.env.production? }
        cart
      end
    end
end
