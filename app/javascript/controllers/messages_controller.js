import { Controller } from "@hotwired/stimulus"
import { nextEventLoopTick } from "helpers/timing_helpers"
import ClientMessage from "models/client_message"
import MessageFormatter, { ThreadStyle } from "models/message_formatter"
import MessagePaginator from "models/message_paginator"
import ScrollManager from "models/scroll_manager"
import ScrollTracker from "models/scroll_tracker"
import StreamRenderQueue from "models/stream_render_queue"

export default class extends Controller {
  static targets = [ "latest", "message", "body", "messages", "template" ]
  static classes = [ "firstOfDay", "firstUnread", "formatted", "me", "mentioned", "mentionedUnread", "threaded", "loadingUp", "loadingDown" ]
  static values = { pageUrl: String }

  #clientMessage
  #paginator
  #formatter
  #scrollManager
  #scrollTracker
  #streamQueue
  #pendingSends = new Map()
  #resizeObserver
  #pinnedToEnd = false
  #scrollTop = 0
  #trackScroll = () => {
    const container = this.messagesTarget
    const maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight)
    const atEnd = maxScrollTop - container.scrollTop <= 4
    // A shrinking scroll range can clamp scrollTop. Only upward movement beyond
    // that clamp releases the anchor, even when geometry changes in the same frame.
    if (atEnd || container.scrollTop < Math.min(this.#scrollTop, maxScrollTop)) {
      this.#pinnedToEnd = atEnd
    }
    this.#scrollTop = container.scrollTop
  }

  // Lifecycle

  initialize() {
    this.#formatter = new MessageFormatter(Current.user.id, {
      firstOfDay: this.firstOfDayClass,
      formatted: this.formattedClass,
      me: this.meClass,
      mentioned: this.mentionedClass,
      mentionedUnread: this.mentionedUnreadClass,
      threaded: this.threadedClass,
    })
  }

  connect() {
    this.#clientMessage = new ClientMessage(this.templateTarget)
    this.#paginator = new MessagePaginator(this.messagesTarget, this.pageUrlValue, this.#formatter, this.#allContentViewed.bind(this), {
      loadingUp: this.loadingUpClass,
      loadingDown: this.loadingDownClass
    })
    this.#scrollManager = new ScrollManager(this.messagesTarget)
    this.#scrollTracker = new ScrollTracker(this.messagesTarget, { lastChildHidden: this.#showReturnToLatestButton.bind(this) })
    this.#streamQueue = new StreamRenderQueue(this.messagesTarget)
    this.#pinnedToEnd = !this.#hasSearchResult && !this.#hasUnreadSeparator
    this.#resizeObserver = new ResizeObserver(() => {
      const container = this.messagesTarget
      // The observer can run before the scroll event for this frame.
      this.#trackScroll()
      if (this.#pinnedToEnd && this.#paginator.upToDate && !this.#paginator.resetting) {
        container.scrollTop = container.scrollHeight
      }
      this.#scrollTop = container.scrollTop
    })
    this.#resizeObserver.observe(this.messagesTarget)
    this.messageTargets.forEach(message => this.#resizeObserver.observe(message))
    this.messagesTarget.addEventListener("scroll", this.#trackScroll, { passive: true })

    if (this.#hasSearchResult) {
      this.#highlightSearchResult()
    } else if (this.#hasUnreadSeparator) {
      this.#scrollToUnreadSeparator()
    } else {
      this.#scrollManager.autoscroll(true)
    }

    if (this.#scrollTracker.scrolledFarFromLatest) {
      this.#showReturnToLatestButton()
    }
    
    this.#paginator.monitor()
    this.#scrollTracker.connect()

  }

  disconnect() {
    this.#resizeObserver.disconnect()
    this.messagesTarget.removeEventListener("scroll", this.#trackScroll)
    this.#paginator.disconnect()
    this.#scrollTracker.disconnect()
    this.#streamQueue.disconnect()
  }

  #streaming = false

  messageTargetConnected(target) {
    if (this.#streaming) target.dataset.new = ""
    this.#formatMessage(target)
    this.#resizeObserver?.observe(target)

    // Fix reply outlet for messages rendered with the default composer_id
    if (target.dataset.replyComposerOutlet) {
      const composerId = this.element.id === "thread-message-area" ? "thread-composer" : "composer"
      target.dataset.replyComposerOutlet = `#${composerId}`
    }
  }

  messageTargetDisconnected(target) {
    this.#resizeObserver?.unobserve(target)
  }

  bodyTargetConnected(target) {
    this.#formatter.formatBody(target)
  }

  // Actions

  async beforeStreamRender(event) {
    const target = event.detail.newStream.getAttribute("target")
    const action = event.detail.newStream.getAttribute("action")
    const render = event.detail.render
    const paginator = this.#paginator
    const reset = paginator.resetting ? paginator.resetToLastPage() : null
    const gate = this.#streamQueue.gateFor(target, reset)

    if (action === "remove" && this.#streamQueue.owns(target)) {
      event.detail.render = async (streamElement) => {
        // A queued append may create this target after the event was received.
        const removedMessage = this.messageTargets.find(el => el.id === target)
        const followingMessage = removedMessage?.nextElementSibling
        await render(streamElement)
        await nextEventLoopTick()
        if (followingMessage?.isConnected) this.#formatMessage(followingMessage)
      }
    }

    if (target === this.messagesTarget.id) {
      if (this.#paginator.upToDate || gate) {
        event.detail.render = async (streamElement) => {
          if (!this.element.isConnected) return

          const didScroll = await this.#scrollManager.autoscroll(false, async () => {
            this.#streaming = true
            try {
              await render(streamElement)
            } finally {
              // Always clear the flag — a throwing render must not leave every
              // later message target marked as newly streamed.
              this.#streaming = false
            }
            await nextEventLoopTick()

            this.#positionLastMessage()
            this.#playSoundForLastMessage()
            this.#paginator.trimExcessMessages(true)
          })
          if (!didScroll) {
            this.#showReturnToLatestButton(true)
          } else {
            this.#pinnedToEnd = true
          }
        }
      } else {
        if (action === "append") event.preventDefault()
        this.#showReturnToLatestButton(true)
      }
    }

    if (gate) {
      event.detail.messageRenderReady = gate
      event.detail.render = this.#streamQueue.enqueue(event.detail.newStream, gate, {
        render: event.detail.render,
        appendsToContainer: target === this.messagesTarget.id,
        isStale: () => this.#paginator !== paginator || !this.element.isConnected
      })
    }
  }

  async returnToLatest() {
    if (!this.#paginator.upToDate) {
      this.latestTarget.classList.add('busy')
    }
    try {
      await this.#ensureUpToDate()
      await this.#scrollManager.autoscroll(true)
      this.#pinnedToEnd = true
      this.#hideReturnToLatestButton()
    } catch (error) {
      if (error.name !== "AbortError") {
        console.warn("[JumpToNewest]", error)
        this.#showReturnToLatestButton()
      }
    } finally {
      this.latestTarget.classList.remove('busy')
    }
  }

  async editMyLastMessage() {
    const composerSelector = this.element.closest("#thread-message-area") ? "#thread-composer lexxy-editor" : "#composer lexxy-editor"
    const editor = document.querySelector(composerSelector)

    // Only act when our own composer or message area has focus — prevents
    // the document-level keydown.up from triggering edits in both the main
    // room and the thread panel simultaneously.
    const focused = document.activeElement
    if (!editor?.contains(focused) && !this.element.contains(focused)) return

    const editorEmpty = editor && editor.isBlank

    if (editorEmpty && this.#paginator.upToDate) {
      this.#myLastMessage?.querySelector(".message__edit-btn")?.click()
    }
  }

  #hideReturnToLatestButton() {
    this.latestTarget.hidden = true
    this.latestTarget.classList.remove('pulse', 'busy')
  }
  
  #showReturnToLatestButton(pulse = false) {
    this.latestTarget.classList.toggle('pulse', pulse)
    this.latestTarget.hidden = false
  }

  // Outlet actions

  async insertPendingMessage(clientMessageId, node) {
    await this.#ensureUpToDate()
    await this.#streamQueue.whenIdle()
    this.#pinnedToEnd = true

    return this.#scrollManager.autoscroll(true, async () => {
      const message = this.#clientMessage.render(clientMessageId, node)
      this.messagesTarget.insertAdjacentHTML("beforeend", message)
    })
  }

  updatePendingMessage(clientMessageId, body) {
    this.#clientMessage.update(clientMessageId, body)
  }

  rememberPendingMessage(clientMessageId, url, formData) {
    this.#pendingSends.set(clientMessageId, { url, formData })
  }

  resolvePendingMessage(clientMessageId) {
    this.#pendingSends.delete(clientMessageId)

    // The real message shares the optimistic node's id (Message#to_key is the
    // client_message_id), so the create stream's append already replaces it by
    // id. Only clear a node still awaiting its server render — real messages
    // carry data-message-id — so a late submit-end never deletes the real one.
    const pending = document.getElementById(`message_${clientMessageId}`)
    if (pending && !pending.dataset.messageId) pending.remove()
  }

  failPendingMessage(clientMessageId) {
    this.#clientMessage.failed(clientMessageId, this.#pendingSends.has(clientMessageId))
  }

  // Re-drives a failed send with its original payload. The server treats a
  // replayed client_message_id as the same message, and the appended response
  // replaces the pending node (Turbo appends dedupe by id) — so this is safe
  // even when the first attempt actually reached the server.
  async retryPendingMessage(event) {
    const clientMessageId = event.params.clientMessageId
    const pending = this.#pendingSends.get(clientMessageId)
    if (!pending) return

    this.#clientMessage.retrying(clientMessageId)

    try {
      // The replayed FormData already carries the form's authenticity_token;
      // the header covers it when the meta tag is present.
      const csrfToken = document.querySelector("meta[name=csrf-token]")?.content

      const response = await fetch(pending.url, {
        method: "POST",
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          ...(csrfToken && { "X-CSRF-Token": csrfToken })
        },
        body: pending.formData,
        credentials: "same-origin"
      })

      // A followed auth redirect answers 200 with a login page, and a rejected
      // send answers 200 HTML — neither is a real create. Only a non-redirected
      // Turbo Stream counts. The saved payload and optimistic node stay put until
      // that stream has rendered, so a failure here still has something to retry.
      const contentType = response.headers.get("content-type") || ""
      if (!response.ok || response.redirected || !contentType.includes("text/vnd.turbo-stream.html")) {
        throw new Error(`Send failed: ${response.status}`)
      }

      Turbo.renderStreamMessage(await response.text())

      this.#pendingSends.delete(clientMessageId)
      // The stream's append replaced the optimistic node in place (both share
      // message_<client_message_id>); only strip one that never got its real
      // render — the real message carries data-message-id.
      const rendered = document.getElementById(`message_${clientMessageId}`)
      if (rendered && !rendered.dataset.messageId) rendered.remove()
    } catch (error) {
      console.warn("[MessageRetry]", error)
      this.#clientMessage.failed(clientMessageId, true)
    }
  }

  // Callbacks

  #allContentViewed() {
    this.#hideReturnToLatestButton()
  }


  // Internal

  async #ensureUpToDate() {
    if (!this.#paginator.upToDate) {
      await this.#paginator.resetToLastPage()
    }
  }

  #highlightSearchResult() {
    const highlightId = location.pathname.split("@").pop()
    const highlightMessage = this.messagesTarget.querySelector(`.message[data-message-id="${highlightId}"]`)
    if (highlightMessage) {
      highlightMessage.classList.add("search-highlight")
      highlightMessage.scrollIntoView({ behavior: "instant", block: "center" })
    }

    const reply = new URLSearchParams(window.location.search).get("reply")
    if (highlightMessage && reply === "true") {
      highlightMessage.querySelector(`button[data-action="reply#reply"]`)?.click()
      this.#removeReplyParam()
    }

    this.#paginator.upToDate = false
  }
  
  #scrollToUnreadSeparator() {
    this.#unreadSeparator.scrollIntoView({ behavior: "instant" })
    const targetTopOffset = window.innerHeight * 0.1;
    const topOffset = this.#unreadSeparator.getBoundingClientRect().top;
    if (topOffset < targetTopOffset) {
      this.messagesTarget.scrollBy(0, topOffset - targetTopOffset); 
    }

    this.#paginator.upToDate = false
  }

  #removeReplyParam() {
    try {
      const url = new URL(window.location);
      url.searchParams.delete("reply");
      window.history.replaceState({}, document.title, url.toString());
    } catch {}
  }

  get #hasSearchResult() {
    return location.pathname.includes("@")
  }
  
  get #hasUnreadSeparator() {
    return !!this.#unreadSeparator
  }

  get #unreadSeparator() {
    return this.messagesTarget.querySelector(`.${this.firstUnreadClass}`)
  }

  get #lastMessage() {
    return this.messagesTarget.children[this.messagesTarget.children.length - 1]
  }

  get #myLastMessage() {
    const myMessages = this.messagesTarget.querySelectorAll(`.${this.meClass}`)
    return myMessages[myMessages.length - 1]
  }

  #positionLastMessage() {
    const followingMessage = this.#followingMessage(this.#lastMessage)

    if (followingMessage) {
      followingMessage.before(this.#lastMessage)
      this.#formatMessage(followingMessage)
    }
  }

  #playSoundForLastMessage() {
    const soundTarget = this.#lastMessage.querySelector(".sound")

    if (soundTarget) {
      this.dispatch("play", { target: soundTarget })
    }
  }

  #followingMessage(message) {
    const messageSortValue = this.#sortValue(message)
    let followingMessage = null
    let previousMessage = message.previousElementSibling

    while (messageSortValue < this.#sortValue(previousMessage)) {
      followingMessage = previousMessage
      previousMessage = previousMessage.previousElementSibling;
    }

    return followingMessage
  }

  #sortValue(node) {
    return (node && parseInt(node.dataset.sortValue)) || 0
  }

  #formatMessage(message) {
    this.#formatter.format(message, ThreadStyle.thread);

    // Also re-format all threaded messages above, to make sure they still need to be threaded
    // (appending current message might have removed the pending message above it and cause inconsistencies in message threads)
    let current = message.previousElementSibling
    while (current && current.classList.contains(this.formattedClass) && current.classList.contains(this.threadedClass)) {
      this.#formatter.format(current, ThreadStyle.thread);
      current = current.previousElementSibling;
    }
  }
}
