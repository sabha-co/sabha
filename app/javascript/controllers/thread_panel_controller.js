import { Controller } from "@hotwired/stimulus"

const TRANSITION_DURATION = 300

export default class extends Controller {
  static targets = ["frame", "panel"]

  connect() {
    this.frameTarget.addEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.addEventListener("turbo:frame-load", this.#onFrameLoad)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.#onFetchStart)
    this.frameTarget.removeEventListener("turbo:frame-load", this.#onFrameLoad)
    clearTimeout(this.#closeTimer)
  }

  open() {
    clearTimeout(this.#closeTimer)
    const generation = ++this.#openGeneration
    this.panelTarget.removeAttribute("hidden")
    // Double rAF: first ensures display change is painted, second triggers transition
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (generation === this.#openGeneration && this.panelTarget.isConnected) {
          document.body.classList.add("thread-panel-open")
        }
      })
    })
  }

  close() {
    this.#dismissPending()
    document.body.classList.remove("thread-panel-open")
    const generation = ++this.#closeGeneration
    this.#closeTimer = setTimeout(() => {
      if (generation === this.#closeGeneration) this.#teardown()
    }, TRANSITION_DURATION)
  }

  #closeTimer
  #closeGeneration = 0
  #openGeneration = 0
  #staleDismiss = false

  closeOnEscape(event) {
    if (event.key === "Escape" && this.#isOpen) {
      this.close()
    }
  }

  // Skip transition on navigation — instant close so layout is clean before Turbo replaces the page
  closeOnNavigation() {
    if (!this.panelTarget.hidden) {
      this.#dismissPending()
      document.body.classList.remove("thread-panel-open")
      this.#teardown()
    }
  }

  get #isOpen() {
    return document.body.classList.contains("thread-panel-open")
  }

  // A fresh load into the panel means a reader explicitly opened its info or a
  // thread, so it supersedes any pending dismissal.
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
      return
    }

    this.open()
  }

  // Mark any in-flight roster/thread load as stale so its frame-load is ignored,
  // and drop the src so nothing reloads it later.
  #dismissPending() {
    this.#openGeneration++
    this.#staleDismiss = true
  }

  #teardown() {
    this.panelTarget.setAttribute("hidden", "")
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }

}
