import { Controller } from "@hotwired/stimulus"

// This controller debounces Turbo Stream updates to prevent race conditions.
// It works by tracking the timestamp of the last update for each channel
// and ignoring any updates that are older than the last one received.
export default class extends Controller {
  static values = {
    timestamps: { type: Object, default: {} }
  }

  connect() {
    this.boundDebounce = this.debounce.bind(this)
    this.element.addEventListener("turbo:before-stream-render", this.boundDebounce)
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-stream-render", this.boundDebounce)
  }

  debounce(event) {
    const newElement = event.detail.newStream.template.content.firstElementChild
    if (!newElement?.dataset.updatedAt) {
      return
    }

    const targetId = event.target.target
    const channelId = this.getChannelId(targetId)
    if (!channelId) {
      return
    }

    const newTimestamp = new Date(newElement.dataset.updatedAt).getTime()
    const lastTimestamp = this.timestampsValue[channelId] || 0

    if (newTimestamp >= lastTimestamp) {
      this.timestampsValue = { ...this.timestampsValue, [channelId]: newTimestamp }
    } else {
      // Stop the rendering if the incoming update is older
      event.preventDefault()
    }
  }

  getChannelId(targetId) {
    const match = targetId.match(/^channel_(\d+)/)
    return match ? match[1] : null
  }
}
