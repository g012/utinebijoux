abort "Demo seeds are development-only" if Rails.env.production?
[
  [ "Éclat de miel", "Bracelets", 2800, 1, true, "bracelet", "Un bracelet lumineux aux reflets miel, assemblé à la main avec des perles de verre et des détails dorés. Une touche chaleureuse à porter chaque jour. Longueur : environ 17 cm + chaînette de réglage. Pièce unique." ],
  [ "Clair de lune", "Colliers", 4200, 1, true, "necklace", "Un collier délicat, entre lumière dorée et douceur des perles. Assemblé à la main, chaque détail a été choisi avec soin. Longueur : environ 40 cm + chaînette de réglage. Pièce unique." ],
  [ "Les inséparables", "Boucles", 2400, 4, false, "earrings", "Une paire de boucles légères, une note dorée pour illuminer le visage. Petite série assemblée à la main. Hauteur : environ 2,5 cm. Vérifiez les matériaux avec l’atelier avant achat si vous avez des sensibilités." ],
  [ "Douce nacre", "Bracelets", 3200, 0, true, "pearls", "Une création douce et lumineuse qui a déjà trouvé son poignet. Elle reste ici comme un souvenir de l’atelier. Pièce unique, vendue." ],
  [ "Fil de lumière", "Colliers", 3600, 1, false, "hero", "Un collier tout en finesse, à porter seul ou à associer à vos bijoux préférés. Assemblé à la main en petite série. Longueur : environ 42 cm. Dernier exemplaire de cette série." ]
].each_with_index do |(name, category, price, stock, unique, image, description), index|
  product = Product.find_or_initialize_by(slug: name.parameterize)
  next if product.persisted?
  product.assign_attributes(name: name, category: category, price_cents: price, stock_quantity: stock, unique_piece: unique, description: description, created_at: (index + 1).hours.ago)
  product.photos.attach(io: File.open(Rails.root.join("public/images/#{image}.jpg")), filename: "#{image}.jpg", content_type: "image/jpeg")
  product.save!
end
puts "Demo creations ready. Photos are illustrative; replace before launch."
