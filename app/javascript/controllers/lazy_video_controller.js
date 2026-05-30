import { Controller } from "@hotwired/stimulus"

// Loads a video's source only as it nears the viewport, so off-screen
// videos download nothing until the visitor scrolls to them. The poster
// stays eager (it's tiny) so there's always an instant placeholder.
export default class extends Controller {
  static values = {
    src: String,
    rootMargin: { type: String, default: "300px" }
  }

  connect() {
    if (!("IntersectionObserver" in window)) return this.#load()

    this.observer = new IntersectionObserver(
      (entries) => { if (entries.some((entry) => entry.isIntersecting)) this.#load() },
      { rootMargin: this.rootMarginValue }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #load() {
    this.observer?.disconnect()
    if (this.loaded) return
    this.loaded = true

    this.element.src = this.srcValue
    this.element.load()
    this.element.play().catch(() => {})
  }
}
