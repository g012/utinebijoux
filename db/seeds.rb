abort "Catalogue seeds are development-only" if Rails.env.production?
products = CatalogImport.call
puts "#{products.size} créations importées. Bagues : 3 € ; autres créations : 6 €."
