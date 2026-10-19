xml.instruct!
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  [ root_path, products_path, about_path, contact_path ].each do |path|
    xml.url { xml.loc "#{Shop.url}#{path}" }
  end
  @products.each do |product|
    xml.url do
      xml.loc "#{Shop.url}#{product_path(product)}"
      xml.lastmod product.updated_at.iso8601
    end
  end
end
