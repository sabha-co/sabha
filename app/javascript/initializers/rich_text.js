import * as Lexxy from "lexxy"
import SabhaRichTextExtension from "lib/rich_text/sabha_extension"

Lexxy.configure({
  global: {
    // Keep the content type of mention attachments (application/vnd.sabha.mention)
    // that Sabha has used since its Trix days
    attachmentContentTypeNamespace: "sabha",
    extensions: [ SabhaRichTextExtension ]
  },
  default: {
    // Hide the editor's file-upload toolbar button — files are sent as separate
    // messages via the composer's own attach button. Attachment SUPPORT stays on
    // (attachments: true, the default): mentions and opengraph embeds are
    // attachments too, and the mention prompt only arms when the editor permits
    // its content type.
    toolbar: { attachments: false },

    // Trix offered a single heading level, rendered as h1
    headings: [ "h1" ]
  }
})
