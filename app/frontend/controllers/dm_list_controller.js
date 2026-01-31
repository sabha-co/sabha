import { Controller } from "@hotwired/stimulus"
import MessagePaginator from "models/message_paginator"

const PAGE_SIZE = 10

export default class extends Controller {
  static targets = ["conversations"]
  static classes = ["loading"]
  static values = { pageUrl: String }

  #paginator

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
