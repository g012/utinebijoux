import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["size", "quantity", "quantityField"]

  connect() { this.update() }

  update() {
    const option = this.sizeTarget.selectedOptions[0]
    const stock = Math.min(Number(option?.dataset.stock || 0), 99)
    this.quantityFieldTarget.hidden = stock <= 1
    this.quantityTarget.max = Math.max(stock, 1)
    this.quantityTarget.value = Math.min(Math.max(Number(this.quantityTarget.value) || 1, 1), Math.max(stock, 1))
  }
}
