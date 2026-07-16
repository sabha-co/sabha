import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { delay, nextFrame } from "helpers/timing_helpers"
import { pageIsTurboPreview } from "helpers/turbo_helpers"

// The heartbeat keeps the server's last-seen from going stale (its TTL is 5
// minutes) and carries the read cursor forward. It no longer has to be frequent:
// the server writes at most once every 4 minutes and ignores the rest, so a
// tighter cadence would buy nothing but RPCs. Must stay under the server's write
// threshold so a watcher never goes stale between their own beats.
const REFRESH_INTERVAL = 2 * 60 * 1000 // 2 minutes

// We delay transmitting visibility changes to ignore brief periods of invisibility,
// like switching to another tab and back
const VISIBILITY_CHANGE_DELAY = 5000 // 5 seconds

export default class extends Controller {
  static values = { roomId: Number }

  async connect() {
    // A cached preview render is not a visit: presenting from one would churn
    // connect/depart writes for a page the reader may never land on.
    if (pageIsTurboPreview()) return

    const roomId = this.roomIdValue || Current.room.id

    this.channel = await cable.subscribeTo({ channel: "PresenceChannel", room_id: roomId }, {
      connected: this.#websocketConnected,
      disconnected: this.#websocketDisconnected
    })

    // Deliberately no `present` here. Subscribing already presents us server
    // side, so sending one too would count this tab twice.
    this.wasVisible = this.#isVisible

    await nextFrame()
    this.dispatch("present", { detail: { roomId } })

    // ...but a tab that (re)subscribes while hidden would then sit in the
    // presence set suppressing its own push notifications. Hand it straight back.
    if (!this.#isVisible) this.channel.send({ action: "absent" })
  }

  disconnect() {
    this.#stopRefreshTimer()
    this.channel?.unsubscribe()
  }

  visibilityChanged = () => {
    if (this.#isVisible) {
      this.#visible()
    } else {
      this.#hidden()
    }
  }

  #websocketConnected = () => {
    this.connected = true
    this.#startRefreshTimer()
  }

  #websocketDisconnected = () => {
    this.connected = false
    this.#stopRefreshTimer()
  }

  #visible = async () => {
    await delay(VISIBILITY_CHANGE_DELAY)

    if (this.connected && this.#isVisible && !this.wasVisible) {
      this.channel.send({ action: "present" })
      this.#startRefreshTimer()
      this.wasVisible = true
    }
  }

  #hidden = async () => {
    await delay(VISIBILITY_CHANGE_DELAY)

    if (this.connected && this.wasVisible && !this.#isVisible) {
      this.#stopRefreshTimer()
      this.channel.send({ action: "absent" })
      this.wasVisible = false
    }
  }

  #startRefreshTimer = () => {
    this.refreshTimer ??= setInterval(this.#refresh, REFRESH_INTERVAL)
  }

  #stopRefreshTimer = () => {
    clearInterval(this.refreshTimer)
    this.refreshTimer = null
  }

  #refresh = () => {
    this.channel.send({ action: "refresh" })
  }

  get #isVisible() {
    return document.visibilityState === "visible"
  }
}
