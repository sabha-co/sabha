import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { pageIsTurboPreview } from "helpers/turbo_helpers"

// How long a person can leave the page alone before their dot stops claiming
// they're available. Mirrors the server's own window, so the two agree about
// where the line is.
const IDLE_AFTER = 10 * 60 * 1000 // 10 minutes

// A busy page fires interaction events constantly; the server only rewrites its
// watermark every couple of minutes anyway, so anything tighter is pure RPC.
const ACTIVE_REPORT_INTERVAL = 2 * 60 * 1000 // 2 minutes

// How coarsely the idle clock is pushed forward. Anything finer is invisible
// against a ten-minute threshold and just churns timers on every mouse move.
const TIMER_RESOLUTION = 5 * 1000 // 5 seconds

// Interaction, not connectivity. The room heartbeat next door proves a tab is
// open, which is a different claim — it keeps ticking through lunch. This
// watches for a human and reports only the edges: went quiet, came back.
export default class extends Controller {
  async connect() {
    if (pageIsTurboPreview()) return

    this.idle = false
    this.lastReportedAt = 0
    this.lastTouchedAt = 0

    this.channel = await cable.subscribeTo({ channel: "HeartbeatChannel" })

    this.#listen()
    this.#restartIdleTimer()
    this.#report(true)
  }

  disconnect() {
    clearTimeout(this.idleTimer)
    this.#stopListening()
    this.channel?.unsubscribe?.()
  }

  #listen() {
    this.onInteraction = this.#interacted.bind(this)

    for (const event of [ "pointerdown", "pointermove", "keydown", "scroll", "touchstart" ]) {
      // Passive so a mousemove listener can never hold up scrolling.
      window.addEventListener(event, this.onInteraction, { passive: true })
    }
    document.addEventListener("visibilitychange", this.onInteraction)
  }

  #stopListening() {
    if (!this.onInteraction) return

    for (const event of [ "pointerdown", "pointermove", "keydown", "scroll", "touchstart" ]) {
      window.removeEventListener(event, this.onInteraction, { passive: true })
    }
    document.removeEventListener("visibilitychange", this.onInteraction)
  }

  // A hidden tab isn't interaction, and shouldn't reset the clock — otherwise
  // tabbing away would keep someone looking available indefinitely.
  //
  // pointermove alone fires ~100x a second, and the only thing most of those
  // events can tell us is something we already know. Coming back from idle is
  // handled immediately; otherwise the clock is only pushed forward every few
  // seconds, which is far finer than the ten-minute question being asked.
  #interacted() {
    if (document.visibilityState !== "visible") return

    if (this.idle) {
      this.idle = false
      this.#restartIdleTimer()
      this.#report(true, { force: true })
      return
    }

    const now = Date.now()
    if (now - this.lastTouchedAt < TIMER_RESOLUTION) return

    this.lastTouchedAt = now
    this.#restartIdleTimer()
    this.#report(true)
  }

  #restartIdleTimer() {
    clearTimeout(this.idleTimer)
    this.idleTimer = setTimeout(() => this.#goIdle(), IDLE_AFTER)
  }

  #goIdle() {
    if (this.idle) return

    this.idle = true
    this.#report(false, { force: true })
  }

  // Edges always go through; "still here" is throttled, since the server would
  // discard most of them anyway.
  #report(active, { force = false } = {}) {
    const now = Date.now()
    if (!force && now - this.lastReportedAt < ACTIVE_REPORT_INTERVAL) return

    this.lastReportedAt = now
    this.channel?.send({ action: "activity", active })
  }
}
