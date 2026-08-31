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
    this.started = false
    this.lastReportedAt = 0
    this.lastTouchedAt = 0

    // Turbo can tear this controller down while the subscription is still in
    // flight. A token captured before the await lets the late continuation
    // notice it's been disconnected and clean up after itself — otherwise it
    // would attach the listeners and arm the timer on a dead controller, and
    // hold a HeartbeatChannel subscription nothing is left to unsubscribe.
    const token = this.connectToken = {}
    const channel = await cable.subscribeTo({ channel: "HeartbeatChannel" }, { connected: this.#socketConnected })

    if (this.connectToken !== token) {
      channel?.unsubscribe?.()
      return
    }

    this.channel = channel
    this.#listen()
    // connected can fire before the await assigns this.channel, so run once more
    // now that a report can actually land — the same belt-and-braces
    // presence_controller uses. The started flag keeps it idempotent.
    this.#socketConnected()
  }

  disconnect() {
    this.connectToken = null
    clearTimeout(this.idleTimer)
    this.#stopListening()
    this.channel?.unsubscribe?.()
    this.channel = null
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

  // Fires when the subscription is confirmed, and again on every reconnect. The
  // first confirmation starts the clock and reports active — waiting for this
  // rather than firing at a socket that isn't open yet and being dropped.
  //
  // A reconnect is the socket blipping, not the human returning: it must not clear
  // idle or push the deadline out, or a tab left idle would spring back to active
  // on its own after any network hiccup. It only resends the state we're already
  // in, so an edge dropped while the socket was down still lands — throttled, so
  // the belt-and-braces double call on first connect doesn't double-report.
  //
  // A tab opened in the background stays silent until it's looked at; reporting on
  // connect would show someone present over a page they never glanced at. The
  // visibilitychange listener brings it in the moment they do.
  #socketConnected = () => {
    if (document.visibilityState !== "visible") return

    if (this.started) {
      this.#report(!this.idle)
    } else {
      this.started = true
      this.#restartIdleTimer()
      this.#report(true, { force: true })
    }
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

    // send returns false when the socket isn't open. Only a delivered report
    // advances the throttle, so one dropped before the connection is up doesn't
    // lock the next real interaction out for the whole two-minute window.
    if (this.channel?.send({ action: "activity", active })) this.lastReportedAt = now
  }
}
