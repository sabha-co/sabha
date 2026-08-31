import { onNextEventLoopTick } from "helpers/timing_helpers"
import ScrollGeometry from "models/scroll_geometry"

const AUTO_SCROLL_THRESHOLD = 100

export default class ScrollManager {
  static #pendingOperations = Promise.resolve()

  #container
  #geometry

  constructor(container) {
    this.#container = container
    this.#geometry = new ScrollGeometry(container)
  }

  async autoscroll(forceScroll, render = () => {}) {
    return this.#appendOperation(async () => {
      const wasNearEnd = this.#scrolledNearEnd

      await render()

      // Update cache after render
      this.#geometry.refresh()

      if (wasNearEnd || forceScroll) {
        this.#container.scrollTop = this.#container.scrollHeight
        return true
      } else {
        return false
      }
    })
  }

  async keepScroll(top, render, scrollBehaviour, delay) {
    return this.#appendOperation(async () => {
      const scrollTop = this.#container.scrollTop
      const scrollHeight = this.#geometry.cachedScrollHeight // Use cached value

      await render()

      // Update cache after render
      this.#geometry.refresh()

      const newScrollTop = top ? scrollTop + (this.#container.scrollHeight - scrollHeight) : scrollTop

      if (delay) {
        requestAnimationFrame(() => this.#container.scrollTo({ top: newScrollTop, behavior: scrollBehaviour }))
      } else {
        this.#container.scrollTo({ top: newScrollTop, behavior: scrollBehaviour })
      }
    })
  }

  // Private

  #appendOperation(operation) {
    ScrollManager.#pendingOperations =
      ScrollManager.#pendingOperations.then(operation)
    return ScrollManager.#pendingOperations
  }

  get #scrolledNearEnd() {
    return this.#geometry.distanceScrolledFromEnd <= AUTO_SCROLL_THRESHOLD
  }
}
