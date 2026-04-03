import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]

  open() {
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  submitted(event) {
    if (event.detail.success) this.close()
  }
}
