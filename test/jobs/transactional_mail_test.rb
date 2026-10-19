require "test_helper"

class TransactionalMailTest < ActiveSupport::TestCase
  test "confirmation marker and both actual Solid Queue jobs commit together" do
    order = reserve
    StripeCheckoutEvent.call(stripe_event(order))
    with_real_mail_queue do
      assert_difference -> { SolidQueue::Job.where(class_name: "TransactionalMailDeliveryJob").count }, 2 do
        2.times { SendOrderConfirmationJob.new.perform(order) }
      end
      assert order.reload.confirmation_enqueued_at
    end
  end

  test "failure enqueueing the second mail rolls back the first job and marker" do
    order = reserve
    StripeCheckoutEvent.call(stripe_event(order))
    with_real_mail_queue do
      OrderMailer.stub(:new_sale, ->(*) { raise "Temporary queue failure" }) do
        assert_no_difference -> { SolidQueue::Job.count } do
          assert_raises(RuntimeError) { SendOrderConfirmationJob.new.perform(order) }
        end
      end
      assert_nil order.reload.confirmation_enqueued_at
    end
  end

  private
    def with_real_mail_queue
      previous_adapter = TransactionalMailDeliveryJob._queue_adapter
      previous_test_adapter = TransactionalMailDeliveryJob._test_adapter
      TransactionalMailDeliveryJob.disable_test_adapter
      TransactionalMailDeliveryJob.queue_adapter = :solid_queue
      yield
    ensure
      TransactionalMailDeliveryJob.queue_adapter = previous_adapter
      TransactionalMailDeliveryJob.enable_test_adapter(previous_test_adapter)
    end
end
