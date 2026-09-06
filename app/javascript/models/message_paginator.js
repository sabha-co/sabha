import { get } from "@rails/request.js"
import {
  insertHTMLFragment,
  parseHTMLFragment,
  keepScroll,
  trimChildren,
} from "helpers/dom_helpers"
import { ThreadStyle } from "models/message_formatter"
import ScrollTracker from "models/scroll_tracker"

const MAX_MESSAGES = 300
const MAX_MESSAGES_LEEWAY = 20

export default class MessagePaginator {
  #container
  #url
  #messageFormatter
  #allContentViewedCallback
  #scrollTracker
  #classes
  #upToDate = true
  #idAttribute
  #resetPromise
  #pageGeneration = 0

  constructor(container, url, messageFormatter, allContentViewedCallback, classes, options = {}) {
    this.#container = container
    this.#url = url
    this.#messageFormatter = messageFormatter
    this.#allContentViewedCallback = allContentViewedCallback
    this.#scrollTracker = new ScrollTracker(container, { lastChildRevealed: this.#messageBecameVisible.bind(this) })
    this.#classes = classes
    this.#idAttribute = options.idAttribute || "messageId"
  }


  // API

  monitor() {
    this.#scrollTracker.connect()
  }

  disconnect() {
    this.#pageGeneration++
    this.#scrollTracker.disconnect()
  }

  get upToDate() {
    return this.#upToDate
  }

  set upToDate(value) {
    this.#upToDate = value
  }

  get resetting() {
    return !!this.#resetPromise
  }

  resetToLastPage() {
    if (!this.#resetPromise) {
      // Responses for the previous history window must never enter this one.
      const generation = ++this.#pageGeneration
      this.upToDate = false
      this.#hideLoadingIndicators()
      this.#resetPromise = this.#showLastPage(generation).finally(() => {
        this.#resetPromise = null
      })
    }
    return this.#resetPromise
  }

  async trimExcessMessages(top) {
    const overage = this.#container.children.length - MAX_MESSAGES
    if (overage > MAX_MESSAGES_LEEWAY) {
      trimChildren(overage, this.#container, top)
      if (!top) {
        this.upToDate = false
      }
    }
  }

  // Internal

  #messageBecameVisible(element) {
    if (this.resetting) return

    const itemId = element.dataset[this.#idAttribute]
    const firstItem = element === this.#container.firstElementChild
    const lastItem = element === this.#container.lastElementChild

    if (itemId) {
      if (firstItem) {
        element.classList.add(this.#classes.loadingUp)
        this.#addPage({ before: itemId }, true)
      }
      if (lastItem && !this.upToDate) {
        element.classList.add(this.#classes.loadingDown)
        this.#addPage({ after: itemId }, false)
      }
      if (lastItem && this.upToDate) {
        this.#allContentViewedCallback?.()
      }
    }
  }

  async #showLastPage(generation) {
    const resp = await this.#fetchPage()
    if (resp.redirected || ![200, 204].includes(resp.statusCode)) {
      throw new Error(`Could not load newest messages: ${resp.statusCode}`)
    }

    const page = resp.statusCode === 204 ? document.createDocumentFragment() : await this.#formatPage(resp)
    if (generation !== this.#pageGeneration) throw new DOMException("Message list disconnected", "AbortError")

    this.#container.replaceChildren(page)
    this.upToDate = true
  }

  async #addPage(params, top) {
    const generation = this.#pageGeneration
    const resp = await this.#fetchPage(params)
    if (generation !== this.#pageGeneration) return

    if (resp.statusCode === 204 && !top) {
      this.upToDate = true
      this.#allContentViewedCallback?.()
    }

    if (resp.statusCode === 200) {
      const page = await this.#formatPage(resp)
      if (generation !== this.#pageGeneration) return
      const lastNewElement = page.lastElementChild

      keepScroll(this.#container, top, () => {
        this.#hideLoadingIndicators()
        insertHTMLFragment(page, this.#container, top)

        // Ensure formatting is correct over page boundaries
        if (top && lastNewElement?.nextElementSibling) {
          this.#messageFormatter.format(lastNewElement.nextElementSibling, ThreadStyle.thread)
        }
      })

      this.trimExcessMessages(!top)
    }

    this.#hideLoadingIndicators()
  }

  async #fetchPage(params) {
    const url = new URL(this.#url)
    for (const param in params) {
      url.searchParams.set(param, params[param])
    }

    return await get(url)
  }

  async #formatPage(response) {
    const text = await response.html
    const fragment = parseHTMLFragment(text)

    for (const message of fragment.querySelectorAll(".message")) {
      this.#messageFormatter.format(message, ThreadStyle.thread)
    }

    return fragment
  }
  
  #hideLoadingIndicators() {
    this.#container.querySelectorAll(`.${this.#classes.loadingUp}`).forEach(el => {
      el.classList.remove(this.#classes.loadingUp);
    });

    this.#container.querySelectorAll(`.${this.#classes.loadingDown}`).forEach(el => {
      el.classList.remove(this.#classes.loadingDown);
    });
  }
}
