import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["main"]
  select(event) {
    this.mainTarget.src = event.currentTarget.dataset.url
    this.element.querySelectorAll("button").forEach(button => button.setAttribute("aria-pressed", button === event.currentTarget))
  }
}
