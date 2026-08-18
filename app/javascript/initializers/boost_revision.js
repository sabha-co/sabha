// Reaction chips render as one grouped frame that is replaced wholesale on every
// change. The submitter's direct Turbo response, the AnyCable broadcast, and
// other people's concurrent reactions can arrive out of order, so an older
// snapshot could otherwise overwrite newer committed state. Each boosts frame
// carries a monotonic data-boost-revision (the message's updated_at); drop any
// replacement whose revision is older than what's already on screen.
addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (!stream || stream.getAttribute("action") !== "replace") return

  const incoming = stream.querySelector("template")?.content.querySelector("[data-boost-revision]")
  if (!incoming) return

  const current = document.getElementById(incoming.id)
  if (!current) return

  if (Number(incoming.dataset.boostRevision) < Number(current.dataset.boostRevision || 0)) {
    event.detail.render = () => {} // stale — a newer reaction state is already shown
  }
})
