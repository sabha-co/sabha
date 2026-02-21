import { DirectUpload } from "@rails/activestorage"

export default class FileUploader {
  constructor(file, directUploadUrl, messageUrl, clientMessageId, progressCallback) {
    this.file = file
    this.directUploadUrl = directUploadUrl
    this.messageUrl = messageUrl
    this.clientMessageId = clientMessageId
    this.progressCallback = progressCallback
  }

  upload() {
    return new Promise((resolve, reject) => {
      const directUpload = new DirectUpload(this.file, this.directUploadUrl, this)

      directUpload.create((error, blob) => {
        if (error) {
          reject(error)
        } else {
          this.#createMessage(blob.signed_id).then(resolve, reject)
        }
      })
    })
  }

  // DirectUpload delegate: called to allow attaching progress listeners
  directUploadWillStoreFileWithXHR(request) {
    request.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100)
        this.progressCallback(percent, this.clientMessageId, this.file)
      }
    })
  }

  #createMessage(signedId) {
    const formdata = new FormData()
    formdata.append("message[attachment]", signedId)
    formdata.append("message[client_message_id]", this.clientMessageId)

    const req = new XMLHttpRequest()
    req.open("POST", this.messageUrl)
    req.setRequestHeader("X-CSRF-Token", document.querySelector("meta[name=csrf-token]").content)

    return new Promise((resolve, reject) => {
      req.addEventListener("readystatechange", () => {
        if (req.readyState === XMLHttpRequest.DONE) {
          if (req.status < 400) {
            resolve(req.response)
          } else {
            reject({ status: req.status, body: req.response })
          }
        }
      })

      req.send(formdata)
    })
  }
}
