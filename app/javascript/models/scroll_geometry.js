// A RAF-batched cache of a container's scrollHeight/clientHeight, plus the derived
// distance from the bottom. Layout reads force reflow and are expensive, so both
// dimensions are read once per animation frame and reused; scrollTop is cheap and
// changes frequently, so it is read live rather than cached.
//
// ScrollManager and ScrollTracker each own an instance — on the messages screen
// three of them share one container, so keeping the cache per-owner (rather than
// shared mutable state) is deliberate: each answers a different "how far from the
// end am I?" question and its staleness is independent.
export default class ScrollGeometry {
  #container
  #cachedScrollHeight = 0
  #cachedClientHeight = 0
  #rafId = null

  constructor(container) {
    this.#container = container
    this.refresh()
  }

  refresh() {
    // Cancel any pending RAF to avoid duplicates
    if (this.#rafId) {
      cancelAnimationFrame(this.#rafId)
    }

    // Use requestAnimationFrame to batch layout reads
    this.#rafId = requestAnimationFrame(() => {
      this.#cachedScrollHeight = this.#container.scrollHeight
      this.#cachedClientHeight = this.#container.clientHeight
      this.#rafId = null
    })
  }

  // Drops a pending measurement — for owners with a teardown (ScrollTracker's
  // disconnect) so a queued RAF can't fire against a detached container.
  cancel() {
    if (this.#rafId) {
      cancelAnimationFrame(this.#rafId)
      this.#rafId = null
    }
  }

  get cachedScrollHeight() {
    return this.#cachedScrollHeight
  }

  get distanceScrolledFromEnd() {
    // Use cached values to avoid forced reflow
    // scrollTop is cheap to read and changes frequently, so we don't cache it
    return this.#cachedScrollHeight - this.#container.scrollTop - this.#cachedClientHeight
  }
}
