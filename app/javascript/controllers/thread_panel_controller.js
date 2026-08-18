import { Controller } from "@hotwired/stimulus"

const TRANSITION_DURATION = 300
const ROSTER_DISMISSED_KEY = "thread-panel:roster-dismissed"

export default class extends Controller {
  static targets = ["frame"]
  static values = { autoSrc: String }

  connect() {
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.addEventListener("turbo:frame-load", this.#onFrameLoad)
    this.#wideViewport = window.matchMedia("(min-width: 1280px)")
    this.#wideViewport.addEventListener("change", this.#onViewportChange)
    this.#autoOpenRoster()
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.removeEventListener("turbo:frame-load", this.#onFrameLoad)
    this.#wideViewport.removeEventListener("change", this.#onViewportChange)
    clearTimeout(this.#closeTimer)
  }

  open() {
    clearTimeout(this.#closeTimer)
    this.element.removeAttribute("hidden")
    // Double rAF: first ensures display change is painted, second triggers transition
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (this.element.isConnected) {
          document.body.classList.add("thread-panel-open")
        }
      })
    })
  }

  close() {
    // Closing the roster is a sticky choice; reopening it from the header
    // clears it again (see #onFrameLoad)
    if (this.#showsRoster) localStorage.setItem(ROSTER_DISMISSED_KEY, "1")

    this.#dismissPending()
    document.body.classList.remove("thread-panel-open")
    const generation = ++this.#closeGeneration
    this.#closeTimer = setTimeout(() => {
      if (generation === this.#closeGeneration) this.#teardown()
    }, TRANSITION_DURATION)
  }

  #closeTimer
  #closeGeneration = 0
  #autoLoaded = false
  #staleDismiss = false
  #wideViewport

  // The ambient roster shouldn't swallow the screen when the viewport narrows
  // into overlay territory — snap it away, without recording a dismissal.
  #onViewportChange = (event) => {
    if (!event.matches && this.#showsRoster && this.#isOpen) {
      this.#dismissPending()
      document.body.classList.remove("thread-panel-open")
      this.#teardown()
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && this.#isOpen) {
      this.close()
    }
  }

  // Skip transition on navigation — instant close so layout is clean before Turbo replaces the page
  closeOnNavigation() {
    if (this.#isOpen) {
      this.#dismissPending()
      document.body.classList.remove("thread-panel-open")
      this.#teardown()
    }
  }

  get #isOpen() {
    return document.body.classList.contains("thread-panel-open")
  }

  // A fresh load into the panel means something wants it open (a thread click or
  // the header reopening the roster), so it supersedes any pending dismissal.
  // Cancel a pending close too — otherwise its teardown can empty this frame and
  // drop its src mid-flight, before the reopen's load lands.
  #onFetchStart = () => {
    clearTimeout(this.#closeTimer)
    this.#closeGeneration++
    this.#staleDismiss = false
  }

  #onFrameLoad = () => {
    // The panel was closed while this load was still in flight — its response
    // arriving now must not reopen the panel.
    if (this.#staleDismiss) {
      this.#staleDismiss = false
      this.#autoLoaded = false
      return
    }

    if (this.#showsRoster && !this.#autoLoaded) localStorage.removeItem(ROSTER_DISMISSED_KEY)
    this.#autoLoaded = false
    this.open()
  }

  // Mark any in-flight roster/thread load as stale so its frame-load is ignored,
  // and drop the src so nothing reloads it later.
  #dismissPending() {
    this.#staleDismiss = true
  }

  #teardown() {
    this.element.setAttribute("hidden", "")
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }

  // Wide screens dock the room roster by default; the reader's dismissal
  // stands until they reopen it themselves.
  #autoOpenRoster() {
    if (!this.autoSrcValue) return
    if (this.frameTarget.getAttribute("src")) return
    if (!window.matchMedia("(min-width: 1280px)").matches) return
    if (localStorage.getItem(ROSTER_DISMISSED_KEY)) return

    this.#autoLoaded = true
    this.frameTarget.src = this.autoSrcValue
  }

  get #showsRoster() {
    return (this.frameTarget.getAttribute("src") || "").includes("/roster")
  }
}
