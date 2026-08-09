import { Controller } from "@hotwired/stimulus"
import FileUploader from "models/file_uploader"
import { onNextEventLoopTick, nextFrame } from "helpers/timing_helpers"
import { escapeHTML } from "helpers/dom_helpers"

export default class extends Controller {
  static classes = ["toolbar"]
  static targets = [ "clientid", "fields", "fileList", "text", "everyoneConfirm", "everyoneConfirmCount", "everyoneConfirmRoomWide" ]
  static values = { roomId: Number, directUploadUrl: String, everyoneConfirmThreshold: Number, everyoneMemberCount: Number, everyoneCapped: Boolean }
  static outlets = [ "messages" ]

  #files = []

  connect() {
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
    this.collapseToolbar()
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
    if (!event.detail.success && this.hasMessagesOutlet) {
      this.messagesOutlet.failPendingMessage(this.clientidTarget.value)
    }
  }

  toggleToolbar() {
    this.element.classList.toggle(this.toolbarClass)
    this.textTarget.focus()
  }

  collapseToolbar() {
    this.element.classList.remove(this.toolbarClass)
  }

  replaceMessageContent(content) {
    const editor = this.textTarget.editor

    editor.recordUndoEntry("Format reply")
    editor.setSelectedRange([0, editor.getDocument().toString().length])
    editor.deleteInDirection("forward")
    editor.insertHTML(content)
    editor.setSelectedRange([editor.getDocument().toString().length - 1])
  }

  submitByKeyboard(event) {
    const toolbarVisible = this.element.classList.contains(this.toolbarClass)
    const metaEnter = event.key == "Enter" && (event.metaKey || event.ctrlKey)
    const plainEnter = event.keyCode == 13 && !event.shiftKey && !event.isComposing

    if (!this.#usingTouchDevice && (metaEnter || (plainEnter && !toolbarVisible))) {
      this.submit(event)
    }
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
      this.element.requestSubmit()
      this.#reset()
    }
  }

  #validInput() {
    return this.textTarget.textContent.trim().length > 0
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
    return Math.random().toString(36).slice(2)
  }

  #reset() {
    this.textTarget.value = ""
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
