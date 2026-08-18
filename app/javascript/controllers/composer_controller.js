import { Controller } from "@hotwired/stimulus"
import { Lexical } from "lexxy"
import FileUploader from "models/file_uploader"
import { onNextEventLoopTick, nextFrame } from "helpers/timing_helpers"
import { escapeHTML } from "helpers/dom_helpers"

export default class extends Controller {
  static targets = [ "clientid", "fields", "fileList", "text", "everyoneConfirm", "everyoneConfirmCount", "everyoneConfirmRoomWide" ]
  static values = { roomId: Number, directUploadUrl: String, everyoneConfirmThreshold: Number, everyoneMemberCount: Number, everyoneCapped: Boolean }
  static outlets = [ "messages" ]

  #files = []
  #pendingClientIds = []

  connect() {
    this.insertFormatBarExtras()

    if (!this.#usingTouchDevice) {
      onNextEventLoopTick(() => this.textTarget.focus())
    }
  }

  submit(event) {
    event.preventDefault()

    if (this.fieldsTarget.disabled) return

    if (this.#needsEveryoneConfirm()) {
      this.#showEveryoneConfirm()
      return
    }

    this.#send()
  }

  confirmEveryone() {
    this.#hideEveryoneConfirm()
    this.#send()
  }

  cancelEveryone() {
    this.#hideEveryoneConfirm()
    this.textTarget.focus()
  }

  #send() {
    this.#submitFiles()
    this.#submitMessage()
    this.textTarget.focus()
  }

  #needsEveryoneConfirm() {
    return this.hasEveryoneConfirmTarget &&
      this.#mentionsEveryone() &&
      this.everyoneMemberCountValue >= this.everyoneConfirmThresholdValue
  }

  #mentionsEveryone() {
    return !!this.textTarget.querySelector(".mention--everyone")
  }

  #showEveryoneConfirm() {
    if (this.hasEveryoneConfirmCountTarget) {
      this.everyoneConfirmCountTarget.textContent = this.everyoneMemberCountValue
    }
    if (this.hasEveryoneConfirmRoomWideTarget) {
      this.everyoneConfirmRoomWideTarget.hidden = !this.everyoneCappedValue
    }
    this.everyoneConfirmTarget.hidden = false
    this.everyoneConfirmTarget.style.display = "flex"
  }

  #hideEveryoneConfirm() {
    if (!this.hasEveryoneConfirmTarget) return
    this.everyoneConfirmTarget.hidden = true
    this.everyoneConfirmTarget.style.display = ""
  }

  submitEnd(event) {
    if (!this.hasMessagesOutlet) return

    const clientMessageId = this.#pendingClientIds.shift() || this.clientidTarget.value

    if (event.detail.success) {
      this.messagesOutlet.resolvePendingMessage(clientMessageId)
    } else {
      this.messagesOutlet.failPendingMessage(clientMessageId)
    }
  }

  // Send only carries the accent fill while there is something to send
  draftChanged() {
    this.element.classList.toggle("composer--drafting", this.#validInput())
  }

  // The persistent format bar is Lexxy's own toolbar; graft the @-mention insert
  // onto it (Lexxy has no native mention button). Lexxy upgrades the editor and
  // builds the toolbar client-side after we connect, so wait for it to appear.
  insertFormatBarExtras() {
    const toolbar = this.textTarget.querySelector("lexxy-toolbar")
    if (toolbar) return this.#graftMentionButton(toolbar)

    const observer = new MutationObserver(() => {
      const bar = this.textTarget.querySelector("lexxy-toolbar")
      if (bar) {
        observer.disconnect()
        this.#graftMentionButton(bar)
      }
    })
    observer.observe(this.textTarget, { childList: true, subtree: true })
  }

  #graftMentionButton(toolbar) {
    if (toolbar.querySelector(".composer__mention-btn")) return

    const button = document.createElement("button")
    button.type = "button"
    button.title = "Mention someone"
    button.className = "lexxy-editor__toolbar-button lexxy-editor__toolbar-group-end composer__mention-btn"
    button.innerHTML = '<span aria-hidden="true">@</span><span class="for-screen-reader">Mention someone</span>'
    // Keep the editor focused so the inserted "@" lands at the caret
    button.addEventListener("mousedown", (event) => event.preventDefault())
    button.addEventListener("click", () => this.insertMention())
    toolbar.appendChild(button)
  }

  insertMention() {
    this.#insertIntoEditor("@")
  }

  // Paired with dialog#close on the emoji grid buttons (see _composer_fields)
  insertEmoji(event) {
    this.#insertIntoEditor(event.params.emoji)
  }

  replaceMessageContent(content) {
    this.textTarget.value = content
    this.textTarget.focus()
    this.textTarget.selection.placeCursorAtTheEnd()
  }

  submitByKeyboard(event) {
    // Runs in the capture phase (see rich_text_data_actions) so it can submit on
    // Enter before the editor turns the keystroke into a newline. Bail while a
    // mention prompt is open so Enter commits the highlighted suggestion instead.
    // The format bar is always on now, so Enter still sends (Shift+Enter is the
    // newline); only bail out for the open prompt and IME composition.
    if (event.key != "Enter" || this.textTarget.hasOpenPrompt) return

    const metaEnter = event.metaKey || event.ctrlKey
    const plainEnter = !event.shiftKey && !event.isComposing
    const shiftEnter = event.shiftKey && !metaEnter && !event.isComposing

    if (!this.#usingTouchDevice && shiftEnter) {
      event.stopPropagation()
      event.preventDefault()
      this.textTarget.editor.dispatchCommand(Lexical.INSERT_PARAGRAPH_COMMAND)
    } else if (!this.#usingTouchDevice && (metaEnter || plainEnter)) {
      event.stopPropagation()
      this.submit(event)
    }
  }

  // Route programmatic inserts through the editor's contenteditable so Lexxy
  // processes them like typing — the "@" opens the mention prompt, an emoji
  // lands as text — and the caret/selection stay correct.
  #insertIntoEditor(text) {
    const content = this.textTarget.querySelector(".lexxy-editor__content")
    content.focus()
    document.execCommand("insertText", false, text)
  }

  filePicked(event) {
    for (const file of event.target.files) {
      this.#files.push(file)
    }
    event.target.value = null
    this.#updateFileList()
  }

  fileUnpicked(event) {
    this.#files.splice(event.params.index, 1)
    this.#updateFileList()
  }

  pasteFiles(event) {
    if (event.clipboardData.files.length > 0) {
      event.preventDefault()
    }

    for (const file of event.clipboardData.files) {
      this.#files.push(file)
    }

    this.#updateFileList()
  }

  dropFiles(event) {
    // When multiple composers are on the page (main + thread), the @window
    // listener fires on all of them. Only handle drops originating from our
    // own element or our associated message area.
    const source = event.target
    const messageArea = this.hasMessagesOutlet ? this.messagesOutlet.element : null
    if (!this.element.contains(source) && !messageArea?.contains(source)) return

    for (const file of event.detail.files) {
      this.#files.push(file)
    }

    this.#updateFileList()
  }

  preventAttachment(event) {
    event.preventDefault()
  }

  online() {
    this.fieldsTarget.disabled = false
  }

  offline() {
    this.fieldsTarget.disabled = true
  }

  get #usingTouchDevice() {
    return 'ontouchstart' in window || navigator.maxTouchPoints > 0 || navigator.msMaxTouchPoints > 0;
  }

  async #submitMessage() {
    if (this.#validInput()) {
      const clientMessageId = this.#generateClientId()

      // No messages outlet when composing the first reply in a provisional thread
      // panel (no thread, so no message stream yet). Skip the optimistic insert and
      // just submit — the server materializes the thread and renders the real panel.
      if (this.hasMessagesOutlet) {
        await this.messagesOutlet.insertPendingMessage(clientMessageId, this.textTarget)
        await nextFrame()
      }

      this.clientidTarget.value = clientMessageId

      // Captured before reset so a failed send can be retried as-submitted
      if (this.hasMessagesOutlet) {
        this.messagesOutlet.rememberPendingMessage(clientMessageId, this.element.action, new FormData(this.element))
        this.#pendingClientIds.push(clientMessageId)
      }

      this.element.requestSubmit()
      this.#reset()
    }
  }

  #validInput() {
    return !this.textTarget.isBlank
  }

  async #submitFiles() {
    // A provisional thread panel has no messages outlet and no room-scoped upload
    // endpoint (the attachment button is hidden there). Drop any dragged/pasted
    // files rather than crash on the missing outlet or POST an attachment with no
    // parent_message_id — attachments work once the thread exists.
    if (!this.hasMessagesOutlet) {
      this.#files = []
      this.#updateFileList()
      return
    }

    const files = this.#files

    this.#files = []
    this.#updateFileList()

    for (const file of files) {
      const clientMessageId = this.#generateClientId()
      const uploader = new FileUploader(file, this.directUploadUrlValue, this.element.action, clientMessageId, this.#uploadProgress.bind(this))

      const body = this.#pendingUploadProgress(file.name)
      await this.messagesOutlet.insertPendingMessage(clientMessageId, body)

      try {
        const resp = await uploader.upload()
        Turbo.renderStreamMessage(resp)
      } catch (error) {
        console.error("[FileUploader]", file.name, error)
        this.messagesOutlet.failPendingMessage(clientMessageId)
      }
    }
  }

  #uploadProgress(percent, clientMessageId, file) {
    const body = this.#pendingUploadProgress(file.name, percent)
    this.messagesOutlet.updatePendingMessage(clientMessageId, body)
  }

  #generateClientId() {
    return crypto.randomUUID()
  }

  #reset() {
    this.textTarget.value = ""
    this.draftChanged()
  }

  #updateFileList() {
    this.#files.sort((a, b) => a.name.localeCompare(b.name))

    const fileNodes = this.#files.map((file, index) => {
      const filename = file.name.split(".").slice(0, -1).join(".")
      const extension = file.name.split(".").pop()

      const node = document.createElement("button")
      node.setAttribute("type","button")
      node.setAttribute("style","gap: 0")
      node.dataset.action = "composer#fileUnpicked"
      node.dataset.composerIndexParam = index
      node.className = "btn btn--plain composer__file txt-normal position-relative unpad flex-column"
      node.innerHTML = file.type.match(/^image\/.*/) ? `<img role="presentation" class="flex-item-no-shrink composer__file-thumbnail" src="${URL.createObjectURL(file)}">` : `<span class="composer__file-thumbnail composer__file-thumbnail--common colorize--black"></span>`
      node.innerHTML += `<span class="pad-inline txt-small flex align-center max-width composer__file-caption"><span class="overflow-ellipsis">${escapeHTML(filename)}.</span><span class="flex-item-no-shrink">${escapeHTML(extension)}</span></span>`

      return node
    })

    this.fileListTarget.replaceChildren(...fileNodes)
  }

  #pendingUploadProgress(filename, percent=0) {
    return `
      <div class="message__pending-upload flex align-center gap" style="--percentage: ${percent}%">
        <div class="composer__file-thumbnail composer__file-thumbnail--common colorize--black borderless flex-item-no-shrink"></div>
        <div>${escapeHTML(filename)} - <span>${percent}%</span></div>
      </div>
    `
  }
}
