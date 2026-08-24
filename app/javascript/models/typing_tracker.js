const REFRESH_INTERVAL = 1000
const TYPING_TIMEOUT = 4000

export default class TypingTracker {
  constructor(callback) {
    this.callback = callback
    this.currentlyTyping = {}
    this.timer = setInterval(this.#refresh.bind(this), REFRESH_INTERVAL)
  }

  // "Naima Okafor is typing" · "Naima and Theo are typing" ·
  // "Naima, Theo and 2 others are typing" — full name alone, first names in
  // company, never more than two names so the row stays one line.
  static label(names) {
    if (names.length === 0) return null
    if (names.length === 1) return `${names[0]} is typing`

    const firstNames = names.map(name => name.split(" ")[0])
    if (names.length === 2) return `${firstNames[0]} and ${firstNames[1]} are typing`

    const others = names.length - 2
    return `${firstNames[0]}, ${firstNames[1]} and ${others} ${others === 1 ? "other" : "others"} are typing`
  }

  close() {
    clearInterval(this.timer)
  }

  add(name) {
    this.currentlyTyping[name] = Date.now()
    this.#refresh()
  }

  remove(name) {
    delete this.currentlyTyping[name]
    this.#refresh()
  }

  #refresh() {
    this.#purgeInactive()
    const names = Object.keys(this.currentlyTyping).sort()
    this.callback(TypingTracker.label(names))
  }

  #purgeInactive() {
    const cutoff = Date.now() - TYPING_TIMEOUT
    this.currentlyTyping = Object.fromEntries(
      Object.entries(this.currentlyTyping).filter(([_name, timestamp]) => timestamp > cutoff)
   )
  }
}
