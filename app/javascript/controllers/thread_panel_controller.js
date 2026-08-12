import { Controller } from "@hotwired/stimulus"

const TRANSITION_DURATION = 300
const ROSTER_DISMISSED_KEY = "thread-panel:roster-dismissed"

export default class extends Controller {
  static targets = ["frame"]
  static values = { autoSrc: String }

  connect() {
    this.frameTarget.addEventListener("turbo:frame-load", this.#onFrameLoad)
    this.#wideViewport = window.matchMedia("(min-width: 1280px)")
    this.#wideViewport.addEventListener("change", this.#onViewportChange)
    this.#autoOpenRoster()
  }

  disconnect() {
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

    document.body.classList.remove("thread-panel-open")
    this.#closeTimer = setTimeout(() => {
      this.element.setAttribute("hidden", "")
      this.frameTarget.innerHTML = ""
    }, TRANSITION_DURATION)
  }

  #closeTimer
  #autoLoaded = false
  #wideViewport

  // The ambient roster shouldn't swallow the screen when the viewport narrows
  // into overlay territory — snap it away, without recording a dismissal.
  #onViewportChange = (event) => {
    if (!event.matches && this.#showsRoster && this.#isOpen) {
      document.body.classList.remove("thread-panel-open")
      this.element.setAttribute("hidden", "")
      this.frameTarget.innerHTML = ""
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
      document.body.classList.remove("thread-panel-open")
      this.element.setAttribute("hidden", "")
      this.frameTarget.innerHTML = ""
    }
  }

  get #isOpen() {
    return document.body.classList.contains("thread-panel-open")
  }

  #onFrameLoad = () => {
    if (this.#showsRoster && !this.#autoLoaded) localStorage.removeItem(ROSTER_DISMISSED_KEY)
    this.#autoLoaded = false
    this.open()
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
