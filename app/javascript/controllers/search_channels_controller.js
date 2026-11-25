import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "container"]

  filter() {
    
    const query = this.inputTarget.value.toLowerCase()
    
    // Get all channel elements within the container
    const channels = this.containerTarget.querySelectorAll("[data-search-text]")

    channels.forEach(channel => {
      const searchText = channel.dataset.searchText.toLowerCase()
      const shouldShow = searchText.includes(query)
      
      channel.style.display = shouldShow ? '' : 'none'
    })
  }
}