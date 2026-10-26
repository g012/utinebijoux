class PagesController < ApplicationController
  allow_unauthenticated_access
  def home
    @products = Product.visible.with_attached_photos.includes(:product_sizes).newest.limit(4)
    @fruit_collection_available = Product.visible.exists?(collection: "Les fruits")
  end
  def about; end
  def contact; end
  def legal
    @title = { "mentions-legales" => "Mentions légales", "conditions-de-vente" => "Conditions générales de vente", "confidentialite" => "Confidentialité" }[params[:page]]
    raise ActiveRecord::RecordNotFound unless @title
  end
  def sitemap
    @products = Product.visible.newest
    response.headers["Cache-Control"] = "public, max-age=3600"
  end
end
