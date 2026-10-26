require "yaml"

# Explicit photo pairs and stable references. Re-running
# only adds missing photos; it never resets prices, stock or editorial changes.
class CatalogImport
  DEMO_SLUGS = %w[eclat-de-miel clair-de-lune les-inseparables douce-nacre fil-de-lumiere].freeze

  def self.call(manifest_path: Rails.root.join("db/catalogue.yml"), photos_directory: Rails.root.join("db/catalogue/photos"))
    entries = YAML.safe_load_file(manifest_path).fetch("products")
    entries.each do |entry|
      entry.fetch("photos").each do |filename|
        raise ArgumentError, "Nom de fichier invalide" unless filename == File.basename(filename)
        raise ArgumentError, "Photo introuvable : #{filename}" unless File.file?(File.join(photos_directory, filename))
      end
    end

    Product.transaction do
      products = entries.map do |entry|
        product = Product.find_or_initialize_by(catalog_reference: entry.fetch("reference"))
        if product.new_record?
          product.assign_attributes(entry.slice("name", "description", "category", "collection", "price_cents", "unique_piece"))
          product.active = entry.fetch("active", false)
          product.save!
        end
        product.with_lock do
          if entry["sizes"].present?
            if !product.sized? && product.order_items.joins(:order).where(orders: { status: "pending_payment" }).exists?
              raise "Une réservation est en cours pour #{product.name} ; attendez sa fin avant d’ajouter les tailles."
            end
            product.update!(unique_piece: false) unless product.sized?
            entry.fetch("sizes").each do |size|
              product.product_sizes.find_or_create_by!(size_cm: size.fetch("size_cm")) do |record|
                record.stock_quantity = size.fetch("stock_quantity", 1)
              end
            end
            product.product_sizes.reset
          end
          existing = product.photos.index_by { |photo| photo.filename.to_s }
          entry.fetch("photos").each do |filename|
            File.open(File.join(photos_directory, filename)) do |file|
              if photo = existing[filename]
                photo.blob.upload_without_unfurling(file) unless photo.blob.service.exist?(photo.blob.key)
              else
                # Upload now: attachment callbacks run after the outer commit,
                # when a block-scoped source IO would already be closed.
                blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: filename, content_type: "image/jpeg")
                product.photos.attach(blob)
              end
            end
          end
          product
        end
      end
      Product.where(catalog_reference: nil, slug: DEMO_SLUGS).update_all(active: false, archived: true)
      products
    end
  end
end
