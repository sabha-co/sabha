import { Controller } from "@hotwired/stimulus"
import { orient } from "helpers/orientation_helpers"

// Reveals the element's own `.for-screen-reader` label as a hover tooltip. The
// visible pill and the accessible name are the same node, so they can never
// drift apart. Showing and hiding is pure CSS (see tooltips.css); this only
// nudges the tooltip away from the viewport edge.
export default class extends Controller {
  connect() {
    this.element.addEventListener("mouseenter", this.#show)
    this.element.addEventListener("mouseleave", this.#hide)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.#show)
    this.element.removeEventListener("mouseleave", this.#hide)
  }

  #show = () => {
    if (this.#tooltipElement) orient({ target: this.#tooltipElement, anchor: this.element })
  }

  #hide = () => {
    if (this.#tooltipElement) orient({ target: this.#tooltipElement, reset: true })
  }

  get #tooltipElement() {
    return this.element.querySelector(".for-screen-reader")
  }
}
