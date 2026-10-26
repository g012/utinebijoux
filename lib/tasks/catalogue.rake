namespace :catalogue do
  desc "Importer les créations de Titine sans écraser les fiches existantes"
  task import: :environment do
    products = CatalogImport.call
    puts "#{products.size} créations · #{products.sum { |product| product.photos.size }} photos."
    puts "Les créations tarifées sont publiées selon le manifeste ; les modifications existantes sont conservées."
  end
end
