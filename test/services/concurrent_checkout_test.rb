require "test_helper"

# Real committed rows and distinct PostgreSQL connections: transactional fixtures
# would hide the inventory from the competing threads.
class ConcurrentCheckoutTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @product = create_product
    @carts = 2.times.map { cart_for(@product) }
  end

  teardown do
    orders = Order.where(cart_id: @carts.map(&:id))
    OrderItem.where(order_id: orders.select(:id)).delete_all
    StripeEvent.where(stripe_id: @event_id).delete_all if @event_id
    orders.delete_all
    CartItem.where(cart_id: @carts.map(&:id)).delete_all
    Cart.where(id: @carts.map(&:id)).delete_all
    Product.where(id: @product.id).delete_all
  end

  test "two simultaneous checkouts cannot reserve the same unique piece" do
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    threads = @carts.map do |cart|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            outcomes << Checkout.reserve(Cart.find(cart.id)).status
          rescue Checkout::Unavailable
            outcomes << "unavailable"
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    assert_equal [ "pending_payment", "unavailable" ], 2.times.map { outcomes.pop }.sort
    assert_equal 0, @product.reload.stock_quantity
    assert_equal 1, OrderItem.where(product_id: @product.id).sum(:quantity)
  end

  test "two simultaneous requests for the same cart reuse one reservation" do
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          results << Checkout.reserve(Cart.find(@carts.first.id)).id
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    assert_equal results.pop, results.pop
    assert_equal 0, @product.reload.stock_quantity
    assert_equal 1, OrderItem.where(product_id: @product.id).sum(:quantity)
  end
  test "two workers delivering the same payment webhook preserve exactly one sale" do
    order = Checkout.reserve(@carts.first)
    event = stripe_event(order)
    @event_id = event.id
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          StripeCheckoutEvent.call(event)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    assert order.reload.paid?
    assert_equal 0, @product.reload.stock_quantity
    assert_equal 1, StripeEvent.where(stripe_id: event.id).count
  end
end
