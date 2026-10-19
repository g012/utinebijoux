import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  move(event) {
    const row = event.currentTarget.closest("[data-photo-row]")
    const previous = row.previousElementSibling
    if (previous) row.parentNode.insertBefore(row, previous)
  }
}
