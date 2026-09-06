import { Controller } from "@hotwired/stimulus"
import ScrollManager from "models/scroll_manager"

export default class extends Controller {
  #scrollManager

  connect() {
    this.#scrollManager = new ScrollManager(this.element)
  }

  // Actions

  beforeStreamRender(event) {
    const shouldKeepScroll = event.detail.newStream.hasAttribute("maintain_scroll")
    const render = event.detail.render
    const target = event.detail.newStream.getAttribute("target")
    const targetElement = document.getElementById(target)

    if (shouldKeepScroll && (this.element.contains(targetElement) || event.detail.messageRenderReady)) {
      const top = targetElement ? this.#isAboveFold(targetElement) : false
      event.detail.render = async (streamElement) => {
        // Wait before entering the shared scroll queue: an earlier message
        // append may need that queue to finish and reveal this stream's target.
        try {
          await event.detail.messageRenderReady
        } catch {
          // Let the ordered renderer settle its pending stream on reset failure.
          return render(streamElement)
        }
        const element = document.getElementById(target)
        if (!this.element.contains(element)) return render(streamElement)
        return this.#scrollManager.keepScroll(
          targetElement ? top : this.#isAboveFold(element),
          () => render(streamElement),
          'auto'
        )
      }
    }
  }

  beforeRender(event) {
    const render = event.detail.render

    event.detail.render = async (...args) => {
      this.#scrollManager.keepScroll(false, () => render(...args), 'instant', true)
    }
  }

  // Internal

  #isAboveFold(element) {
    return element.getBoundingClientRect().top < this.element.clientHeight
  }
}
