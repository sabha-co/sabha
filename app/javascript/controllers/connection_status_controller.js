import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

// Shows a "reconnecting" banner whenever the realtime socket drops. When the
// WebSocket dies every channel subscription is disconnected together, so a
// lightweight HeartbeatChannel subscription is a faithful proxy for the
// connection itself — no extra socket, no polling.
export default class extends Controller {
  static classes = [ "visible" ]

  async connect() {
    this.channel = await cable.subscribeTo({ channel: "HeartbeatChannel" }, {
      connected: () => this.#online(),
      disconnected: () => this.#offline(),
      rejected: () => this.#offline()
    })
  }

  disconnect() {
    this.channel?.unsubscribe?.()
  }

  #online() {
    this.element.classList.remove(this.visibleClass)
  }

  #offline() {
    this.element.classList.add(this.visibleClass)
  }
}
