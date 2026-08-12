import { Controller } from "@hotwired/stimulus"

// Live-filters the sidebar's room and person rows by name. Purely
// presentational: rows hide via [hidden] and reappear when the query clears.
export default class extends Controller {
  static targets = [ "input" ]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()

    this.#rows.forEach(row => {
      const name = (row.dataset.name || row.textContent).toLowerCase()
      row.hidden = query !== "" && !name.includes(query)
    })
  }

  clear() {
    this.inputTarget.value = ""
    this.filter()
  }

  get #rows() {
    return this.element.querySelectorAll("[data-type=list_node], .direct")
  }
}
