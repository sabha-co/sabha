import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { content: String, label: String }
  static classes = [ "success" ]
  static targets = [ "label", "toast" ]

  async copy(event) {
    event.preventDefault()
    this.reset()

    try {
      await navigator.clipboard.writeText(this.contentValue)
      if (this.hasSuccessClass) this.element.classList.add(this.successClass)
      this.#confirmCopied()
    } catch {}
  }

  reset() {
    if (this.hasSuccessClass) this.element.classList.remove(this.successClass)
    this.#forceReflow()
  }

  // Swap the button label to "Copied" for a beat, and raise a toast — both
  // opt-in, so the plain icon copy button (invite link) is unaffected.
  #confirmCopied() {
    this.#swapLabel()
    this.#raiseToast()
  }

  #swapLabel() {
    if (!this.hasLabelTarget || !this.hasLabelValue) return

    this.originalLabel ??= this.labelTarget.textContent
    this.labelTarget.textContent = this.labelValue
    clearTimeout(this.labelTimeout)
    this.labelTimeout = setTimeout(() => {
      this.labelTarget.textContent = this.originalLabel
    }, 1600)
  }

  #raiseToast() {
    if (this.hasToastTarget) {
      document.body.appendChild(this.toastTarget.content.cloneNode(true))
    }
  }

  disconnect() {
    clearTimeout(this.labelTimeout)
  }

  #forceReflow() {
    this.element.offsetWidth
  }
}
