import { Controller } from "@hotwired/stimulus"

// Opens the forum's inline "New post" composer from outside the composer's own
// DOM subtree — the top nav renders in a separate part of the page (content_for
// :nav), so it reaches the forum-compose controller through a Stimulus outlet.
export default class extends Controller {
  static outlets = ["forum-compose"]

  open(event) {
    event.preventDefault()
    if (this.hasForumComposeOutlet) this.forumComposeOutlet.open()
  }
}
