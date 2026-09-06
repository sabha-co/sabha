// Serializes the Turbo stream renders that arrive while the message list is
// being reset to its latest page (a "Jump to newest"). Each stream that
// targets the list — or a message that only exists inside an append still
// waiting in the queue — renders in arrival order behind the reset. That keeps
// a late edit or removal from landing before the append that creates its
// target, and stops new messages from being appended across the history gap a
// failed jump never loaded.
export default class StreamRenderQueue {
  #container
  #tail            // Promise settling when the render at the back of the queue finishes
  #targets = new Set()

  constructor(container) {
    this.#container = container
  }

  disconnect() {
    this.#tail = null
    this.#targets.clear()
  }

  // Does the message list own this target: the list itself, a message inside it,
  // or a message that only exists inside an append still queued ahead of us?
  owns(target) {
    return target === this.#container.id ||
      this.#container.contains(document.getElementById(target)) ||
      this.#targets.has(target)
  }

  // Wait until queued renders finish (optimistic inserts must not overtake them).
  whenIdle() {
    return this.#tail ? this.#tail.then(() => {}) : Promise.resolve()
  }

  // The promise a stream for `target` must wait behind before rendering, or null
  // when nothing is in flight and it can render immediately. `reset` is the
  // paginator's in-progress reset, if any.
  gateFor(target, reset) {
    if (!this.owns(target)) return null
    const tail = this.#tail
    if (!tail && !reset) return null

    // Order behind the current tail, but take jump success from this stream's
    // reset — a failed jump's finish(false) must not skip appends on a retry.
    return (async () => {
      if (tail) await Promise.resolve(tail).catch(() => {})
      if (reset) {
        await reset
        return true
      }
      return await Promise.resolve(tail)
    })()
  }

  // Wraps `render` so it runs only after `gate` settles, preserving stream order.
  // `appendsToContainer` marks a new-message append (versus an edit/removal of an
  // existing target); `isStale` reports when the controller has moved on.
  enqueue(newStream, gate, { render, appendsToContainer, isStale }) {
    this.#registerTargets(newStream)

    let finish
    const completed = new Promise(resolve => { finish = resolve })
    this.#tail = completed

    return async (streamElement) => {
      let historyLoaded = false
      try {
        // The gate resolves false only when the render ahead of us could not
        // append its history (a failed jump); a rejected gate means the same.
        historyLoaded = await Promise.resolve(gate).catch(() => false) !== false
        if (isStale()) return
        // A failed jump keeps its old history: edits and removals still apply to
        // it, but new messages must not be appended across the gap it never loaded.
        if (historyLoaded || !appendsToContainer) await render(streamElement)
      } catch (error) {
        if (error.name !== "AbortError") console.warn("[MessageStream]", error)
      } finally {
        finish(historyLoaded)
        if (this.#tail === completed) {
          this.#tail = null
          this.#targets.clear()
        }
      }
    }
  }

  #registerTargets(newStream) {
    this.#targets.add(newStream.getAttribute("target"))
    for (const element of newStream.querySelector("template")?.content.querySelectorAll("[id]") || []) {
      this.#targets.add(element.id)
    }
  }
}
