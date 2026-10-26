class Checkout
  class Unavailable < StandardError; end
  class NotConfigured < StandardError; end
  def self.start(cart)
    raise NotConfigured unless Stripe.api_key.present?
    order = reserve(cart)
    session_for(order)
    order.reload
  end

  def self.reserve(cart)
    cart.with_lock do
      return cart.pending_order if cart.pending_order
      items = cart.cart_items.order(:product_id).to_a
      raise Unavailable, "Votre panier est vide." if items.empty?
      products = Product.where(id: items.map(&:product_id)).order(:id).lock.index_by(&:id)
      sizes = ProductSize.where(id: items.map(&:product_size_id).compact).order(:id).lock.index_by(&:id)
      items.each do |item|
        product = products.fetch(item.product_id)
        size = sizes[item.product_size_id]
        if product.sized? != size.present? || (size && size.product_id != product.id)
          raise Unavailable, "Veuillez choisir une taille disponible pour #{product.name}."
        end
        inventory = size || product
        unless product.purchasable? && item.quantity <= inventory.stock_quantity && (size || !product.unique_piece? || item.quantity == 1)
          raise Unavailable, "Désolé, cette pièce vient d’être vendue ou n’est plus disponible : #{product.name}."
        end
      end
      subtotal = items.sum { |item| products.fetch(item.product_id).price_cents * item.quantity }
      order = cart.orders.build(subtotal_cents: subtotal, shipping_cents: Shop.shipping_cents,
        total_cents: subtotal + Shop.shipping_cents, expires_at: 35.minutes.from_now.change(usec: 0))
      items.each do |item|
        product = products.fetch(item.product_id)
        size = sizes[item.product_size_id]
        order.order_items.build(product: product, product_size: size, size_cm: size&.size_cm,
          product_name: product.name, unit_price_cents: product.price_cents, quantity: item.quantity)
        inventory = size || product
        inventory.update!(stock_quantity: inventory.stock_quantity - item.quantity)
      end
      # Persist the exact request, including URLs, for idempotent recovery after a crash.
      order.valid? # assigns the human-readable reference
      order.checkout_request = request_for(order)
      order.save!
      cart.cart_items.delete_all
      order
    end
  end

  def self.session_for(order)
    rejection = nil
    order.with_lock do
      return unless order.pending_payment?
      return Stripe::Checkout::Session.retrieve(order.stripe_session_id) if order.stripe_session_id
      if order.expires_at.past?
        # Beyond the original expiry, discover a session that may have been
        # created before a lost response. Never blindly replay an aged key.
        session = Stripe::Checkout::Session.list(created: { gte: order.created_at.to_i - 60 }, limit: 100).auto_paging_each.find do |candidate|
          candidate.metadata["order_token"] == order.public_token
        end
        if session
          order.update!(stripe_session_id: session.id, checkout_url: session.url, expires_at: Time.at(session.expires_at))
        else
          order.release!(:expired)
        end
        return
      end
      begin
        session = Stripe::Checkout::Session.create(order.checkout_request.deep_symbolize_keys,
          { idempotency_key: "checkout-#{order.public_token}" })
      rescue Stripe::InvalidRequestError => error
        # Definitive rejection: no payable session was created. Network errors are
        # intentionally NOT released, because Stripe may have accepted the request.
        order.release!(:cancelled)
        rejection = error
      else
        order.update!(stripe_session_id: session.id, checkout_url: session.url, expires_at: Time.at(session.expires_at))
      end
    end
    raise rejection if rejection
  end

  def self.request_for(order)
    {
      mode: "payment", locale: "fr", payment_method_types: [ "card" ],
      billing_address_collection: "required", shipping_address_collection: { allowed_countries: [ "FR" ] },
      client_reference_id: order.number, metadata: { order_token: order.public_token },
      expires_at: order.expires_at.to_i,
      success_url: "#{Shop.url}/commandes/#{order.public_token}", cancel_url: "#{Shop.url}/panier",
      line_items: order.order_items.map { |item| { quantity: item.quantity, price_data: {
        currency: order.currency, unit_amount: item.unit_price_cents, product_data: { name: item.display_name }
      } } },
      shipping_options: [ { shipping_rate_data: { type: "fixed_amount", display_name: "Livraison en France",
        fixed_amount: { amount: order.shipping_cents, currency: order.currency } } } ]
    }
  end
end
