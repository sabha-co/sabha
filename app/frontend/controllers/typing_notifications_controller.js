import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { throttle } from "helpers/timing_helpers"
import { pageIsTurboPreview } from "helpers/turbo_helpers"
import TypingTracker from "models/typing_tracker"

export default class extends Controller {
  static targets = [ "author", "indicator" ]
  static classes = [ "active" ]

  async connect() {
    if (pageIsTurboPreview()) return

    this.tracker = new TypingTracker(this.#update.bind(this))
    this.whisperEnabled = false

    // Try AnyCable client for whisper support (bypasses Rails RPC)
    if (await this.#setupAnyCable()) return

    // Fall back to standard ActionCable
    this.channel = await cable.subscribeTo(
      { channel: "TypingNotificationsChannel", room_id: Current.room.id },
      { received: this.#received.bind(this) }
    )
  }

  disconnect() {
    this.tracker?.close()
    this.channel?.disconnect?.() || this.channel?.unsubscribe?.()
    this.cable?.disconnect?.()
  }

  start({ target }) {
    if (target.value) {
      this.#throttledSend("start")
    } else {
      this.#send("stop")
    }
  }

  stop() {
    this.#send("stop")
  }

  async #setupAnyCable() {
    try {
      // Only use AnyCable whisper if explicitly enabled via meta tag
      const whisperEnabled = document.querySelector('meta[name="anycable-whisper"]')?.content === "true"
      if (!whisperEnabled) return false

      const { createCable, Channel } = await import("@anycable/web")

      class TypingChannel extends Channel {
        static identifier = "TypingNotificationsChannel"
      }

      // createCable() uses action-cable-url meta tag automatically
      this.cable = createCable()
      this.channel = new TypingChannel({ room_id: Current.room.id })
      this.cable.subscribe(this.channel)
      this.channel.on("message", this.#received.bind(this))
      this.whisperEnabled = true
      return true
    } catch (e) {
      console.debug("[Typing] AnyCable unavailable, using ActionCable:", e.message)
      return false
    }
  }

  #received = (data) => {
    if (data.user?.id !== Current.user.id) {
      if (data.action === "start") {
        this.tracker.add(data.user.name)
      } else {
        this.tracker.remove(data.user.name)
      }
    }
  }

  #send(action) {
    if (this.whisperEnabled) {
      this.channel.whisper({ action, user: { id: Current.user.id, name: Current.user.name } })
    } else {
      this.channel.send({ action })
    }
  }

  #update(message) {
    this.authorTarget.textContent = message
    this.indicatorTarget.classList.toggle(this.activeClass, !!message)
  }

  #throttledSend = throttle(action => this.#send(action))
}
