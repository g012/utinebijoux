module ApplicationHelper
  def money(cents)
    number_to_currency(cents.to_i / 100.0, unit: "€", separator: ",", delimiter: " ", format: "%n %u")
  end
  def page_title = content_for(:title).presence || "Bijoux faits main, petites merveilles du quotidien"
  def page_description = content_for(:description).presence || "Des bijoux en perles faits main, imaginés avec soin. Pièces uniques et petites séries à découvrir. Livraison en France."
  def product_photo(product, **options)
    if photo = product.ordered_photos.first
      image_tag photo, alt: "#{product.name} — bijou fait main", loading: "lazy", **options
    else
      tag.div("Photographie à venir", class: "photo-placeholder", role: "img", "aria-label": product.name)
    end
  end
  def icon(name, size: 22)
    paths = {
      bag: '<path d="M5 7h14l1 14H4L5 7Z"/><path d="M8 8V6a4 4 0 0 1 8 0v2"/>',
      arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
      star: '<path d="m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5L12 2Z"/>',
      heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
      check: '<path d="m5 12 4 4L19 6"/>',
      truck: '<path d="M2 5h12v12H2zM14 9h4l4 5v3h-8"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>',
      close: '<path d="m6 6 12 12M6 18 18 6"/>'
    }
    tag.svg(paths.fetch(name.to_sym).html_safe, width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.4", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
  end
  def product_json_ld(product)
    data = { "@context" => "https://schema.org", "@type" => "Product", name: product.name, description: product.description,
      url: "#{Shop.url}#{product_path(product)}", offers: { "@type" => "Offer", price: format("%.2f", product.price_cents / 100.0), priceCurrency: "EUR",
        availability: product.purchasable? ? "https://schema.org/InStock" : "https://schema.org/OutOfStock", url: "#{Shop.url}#{product_path(product)}" } }
    data[:image] = product.ordered_photos.map { |photo| url_for(photo) } if product.photos.attached?
    data[:size] = product.product_sizes.map(&:label) if product.sized?
    tag.script(json_escape(data.to_json).html_safe, type: "application/ld+json")
  end
end
