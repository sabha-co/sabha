import ScrollGeometry from "models/scroll_geometry"

const SCROLLED_AWAY_FROM_LATEST_THRESHOLD = 500

export default class ScrollTracker {
    #container
    #lastChildRevealedCallback
    #lastChildHiddenCallback
    #intersectionObserver
    #mutationObserver
    #firstChildWasHidden
    #geometry

    constructor(container, { lastChildRevealed, lastChildHidden }) {
        this.#container = container
        this.#lastChildRevealedCallback = lastChildRevealed
        this.#lastChildHiddenCallback = lastChildHidden

        this.#mutationObserver = new MutationObserver(this.#childrenChanged.bind(this))

        this.#intersectionObserver = new IntersectionObserver(this.#handleIntersection.bind(this), {root: container})

        this.#geometry = new ScrollGeometry(container)
    }

    connect() {
        this.#mutationObserver.observe(this.#container, {childList: true})
        this.#childrenChanged()
    }

    disconnect() {
        this.#mutationObserver?.disconnect()
        this.#intersectionObserver?.disconnect()
        this.#geometry?.cancel()
    }

    #childrenChanged() {
        this.#intersectionObserver?.disconnect()

        if (this.#container.firstElementChild) {
            this.#firstChildWasHidden = false

            this.#intersectionObserver?.observe(this.#container.firstElementChild)
            this.#intersectionObserver?.observe(this.#container.lastElementChild)
        }

        // Update cached values when DOM changes
        this.#geometry.refresh()
    }

    #handleIntersection(entries) {
        for (const entry of entries) {
            // Don't callback when the first child is shown, unless it had previously
            // been hidden. This avoids the issue that adding new pages will always
            // fire the callback for the first item before the scroll position is
            // adjusted.
            //
            // We don't do this with the last item, because it's possible that
            // fetching a page could return less than a screenfull.
            const isFirst = entry.target === this.#container.firstElementChild
            const significantReveal = (isFirst && this.#firstChildWasHidden) || !isFirst

            if (entry.isIntersecting) {
                if (significantReveal) {
                    this.#lastChildRevealedCallback?.(entry.target)
                }
            } else {
                if (isFirst) {
                    this.#firstChildWasHidden = true
                } else {
                    this.#lastChildHiddenCallback?.()
                }
            }
        }
    }

    get scrolledFarFromLatest() {
        return this.#geometry.distanceScrolledFromEnd > SCROLLED_AWAY_FROM_LATEST_THRESHOLD
    }
}
