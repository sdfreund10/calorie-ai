import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "panel"]

  open() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")

    if (this.#prefersReducedMotion) {
      this.overlayTarget.classList.add("drawer--open")
      return
    }

    this.overlayTarget.classList.remove("drawer--open")
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.overlayTarget.classList.add("drawer--open")
      })
    })
  }

  close() {
    if (!this.hasOverlayTarget) return

    if (this.#prefersReducedMotion) {
      this.overlayTarget.classList.remove("drawer--open")
      this.overlayTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
      return
    }

    if (!this.overlayTarget.classList.contains("drawer--open")) {
      this.overlayTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
      return
    }

    let settled = false
    const finish = () => {
      if (settled) return
      settled = true
      window.clearTimeout(fallback)
      this.overlayTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
      if (this.hasPanelTarget) {
        this.panelTarget.removeEventListener("transitionend", onTransitionEnd)
      }
    }

    const onTransitionEnd = (event) => {
      if (event.propertyName !== "transform") return
      finish()
    }

    const fallback = window.setTimeout(finish, 450)

    if (this.hasPanelTarget) {
      this.panelTarget.addEventListener("transitionend", onTransitionEnd)
    }

    this.overlayTarget.classList.remove("drawer--open")
  }

  submitted(event) {
    if (event.detail.success) this.close()
  }

  get #prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
