import { Controller } from "@hotwired/stimulus"
import { onNextEventLoopTick } from "helpers/timing_helpers"

export default class extends Controller {
  static values = {
    originalTitle: String
  }

  connect() {
    // Bind the event handlers once to maintain the same reference
    this.boundUpdateTitle = this.updateTitle.bind(this)
    this.boundCheckTitle = this.checkTitle.bind(this)
    
    // Store the original page title when the controller connects
    this.originalTitleValue = document.title
    
    // Listen for unread and badge events from channels-list
    window.addEventListener("channels-list:unread", this.boundUpdateTitle)
    window.addEventListener("channels-list:read", this.boundUpdateTitle)
    window.addEventListener("channels-list:addBadge", this.boundUpdateTitle)
    
    // Listen for Turbo navigation events
    document.addEventListener("turbo:before-render", this.boundCheckTitle)
    
    // Initial update
    onNextEventLoopTick(this.boundUpdateTitle)
  }

  disconnect() {
    // Clean up event listeners
    window.removeEventListener("channels-list:unread", this.boundUpdateTitle)
    window.removeEventListener("channels-list:read", this.boundUpdateTitle)
    window.removeEventListener("channels-list:addBadge", this.boundUpdateTitle)
    
    // Clean up Turbo navigation event listeners
    document.removeEventListener("turbo:before-render", this.boundCheckTitle)
    
    // Restore original title
    document.title = this.originalTitleValue
  }
  
  // Check if the title has changed
  checkTitle() {
    const currentTitle = document.title
    
    // If the title has changed and doesn't have our indicators, update our stored value
    if (currentTitle !== this.originalTitleValue && 
        !currentTitle.startsWith('🔴') && 
        !currentTitle.startsWith('⚫')) {
      this.originalTitleValue = currentTitle
      this.updateTitle()
    }
  }

  updateTitle() {
    const sidebar = document.getElementById("sidebar")
    if (!sidebar) {
      document.title = this.originalTitleValue
      return
    }

    if (sidebar.querySelector(".badge") || sidebar.querySelector(".direct.unread")) {
      document.title = `🔴 ${this.originalTitleValue}`
    } else if (sidebar.querySelector("#starred_channels [data-type=list_node]:not([hidden]) .unread")) {
      document.title = `⚫ ${this.originalTitleValue}`
    } else {
      document.title = this.originalTitleValue
    }
  }
}
