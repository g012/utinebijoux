# All boutique settings live here; order prices are snapshotted at reservation time.
module Shop
  def self.name = ENV.fetch("SHOP_NAME", "Nom de l’atelier")
  def self.email = ENV.fetch("SHOP_EMAIL", "bonjour@example.com")
  def self.admin_email = ENV.fetch("ADMIN_EMAIL", email)
  def self.url = ENV.fetch("APP_URL", "http://localhost:3000").delete_suffix("/")
  def self.shipping_cents = Integer(ENV.fetch("FRANCE_SHIPPING_CENTS", "490"))
  def self.currency = "eur"
end

Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
Stripe.max_network_retries = 2
