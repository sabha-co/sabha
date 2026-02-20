import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers/timing_helpers"
import { normalize } from "lib/autocomplete/utils"

export default class extends Controller {
  static targets = [ "input", "item", "summary" ]

  initialize() {
    this.filter = debounce(this.filter.bind(this), 100)
  }

  filter() {
    const query = this.inputTarget.value

    if (query === "") {
      this.#restoreDefaults()
    } else {
      this.#filterItems(query)
    }
  }

  #restoreDefaults() {
    this.itemTargets.forEach(item => {
      item.hidden = item.hasAttribute("data-filter-default")
    })
    if (this.hasSummaryTarget) this.summaryTarget.hidden = false
  }

  #filterItems(query) {
    this.itemTargets.forEach(item => {
      if (normalize(item.textContent.toLowerCase()).includes(normalize(query.toLowerCase()))) {
        item.removeAttribute("hidden")
      } else {
        item.toggleAttribute("hidden", true)
      }
    })
    if (this.hasSummaryTarget) this.summaryTarget.toggleAttribute("hidden", true)
  }
}
