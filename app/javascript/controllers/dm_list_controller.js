import { Controller } from "@hotwired/stimulus"
import MessagePaginator from "models/message_paginator"

const PAGE_SIZE = 10

export default class extends Controller {
  static targets = ["conversations", "conversation"]
  static classes = ["loading"]
  static values = { pageUrl: String, pinnedRoomId: String }

  #paginator

  // Runs for every row present at connect and for stream-inserted rows, so
  // the open conversation stays highlighted across live updates
  conversationTargetConnected(element) {
    this.#markCurrentConversation()
    this.#dropPinnedDuplicate(element)
  }

  // The open conversation is pinned above the list when it's fallen off the
  // first page. If pagination later loads that same room into the list, drop the
  // in-list copy so it isn't shown twice.
  #dropPinnedDuplicate(element) {
    if (this.pinnedRoomIdValue && element.dataset.roomId === this.pinnedRoomIdValue) {
      element.remove()
    }
  }

  #markCurrentConversation() {
    const current = document.querySelector("meta[name='current-room-id']")?.content
    for (const row of this.conversationTargets) {
      row.classList.toggle("dm-conversation--current", !!current && row.dataset.roomId === current)
    }
  }

  connect() {
    // Use a no-op formatter since DM conversations don't need message formatting
    const noOpFormatter = { format: () => {} }

    this.#paginator = new MessagePaginator(
      this.conversationsTarget,
      this.pageUrlValue,
      noOpFormatter,
      () => {},
      {
        loadingUp: this.loadingClass,
        loadingDown: this.loadingClass
      },
      { idAttribute: "roomId" }
    )

    // DMs start "not up to date" so scrolling down loads more
    this.#paginator.upToDate = this.conversationsTarget.children.length < PAGE_SIZE
    this.#paginator.monitor()
  }

  disconnect() {
    this.#paginator.disconnect()
  }
}
