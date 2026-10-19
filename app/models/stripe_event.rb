class StripeEvent < ApplicationRecord
  validates :stripe_id, uniqueness: true
end
