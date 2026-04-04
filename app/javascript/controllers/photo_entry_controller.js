import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "libraryInput",
    "cameraInput",
    "uploadPrompt",
    "preview",
    "previewImg",
    "actions",
    "analyzeForm",
    "manualForm",
    "analyzeSubmit",
    "description",
  ]

  connect() {
    this.previewUrl = null
  }

  disconnect() {
    this.revokePreviewUrl()
  }

  pickLibrary() {
    this.libraryInputTarget.click()
  }

  pickCamera() {
    this.cameraInputTarget.click()
  }

  fileChosen(event) {
    const file = event.target.files?.[0]
    if (!file) {
      this.clearPreview()
      return
    }

    this.revokePreviewUrl()
    this.previewUrl = URL.createObjectURL(file)
    this.previewImgTarget.src = this.previewUrl
    if (this.hasUploadPromptTarget) this.uploadPromptTarget.classList.add("hidden")
    this.previewTarget.classList.remove("hidden")
    this.actionsTarget.classList.remove("hidden")

    this.syncFileToForms(event.target)
  }

  syncFileToForms(sourceInput) {
    const file = sourceInput.files?.[0]
    if (!file) return

    ;[this.analyzeFormTarget, this.manualFormTarget].forEach((formEl) => {
      const input = formEl.querySelector('input[type="file"][name*="[image]"]')
      if (!input) return

      const dt = new DataTransfer()
      dt.items.add(file)
      input.files = dt.files
    })
  }

  syncDescription() {
    if (!this.hasDescriptionTarget) return
    const value = this.descriptionTarget.value
    ;[this.analyzeFormTarget, this.manualFormTarget].forEach((formEl) => {
      const field = formEl.querySelector('[name="user_description"]')
      if (field) field.value = value
    })
  }

  clearPreview() {
    this.revokePreviewUrl()
    this.previewImgTarget.removeAttribute("src")
    this.previewTarget.classList.add("hidden")
    if (this.hasUploadPromptTarget) this.uploadPromptTarget.classList.remove("hidden")
    this.actionsTarget.classList.add("hidden")
    ;[this.libraryInputTarget, this.cameraInputTarget].forEach((el) => {
      el.value = ""
    })
    ;[this.analyzeFormTarget, this.manualFormTarget].forEach((formEl) => {
      const input = formEl.querySelector('input[type="file"][name*="[image]"]')
      if (input) input.value = ""
    })
  }

  revokePreviewUrl() {
    if (this.previewUrl) {
      URL.revokeObjectURL(this.previewUrl)
      this.previewUrl = null
    }
  }

  startAnalyzeLoading() {
    if (!this.hasAnalyzeSubmitTarget) return
    this.analyzeSubmitTarget.disabled = true
    if (!this.analyzeSubmitTarget.dataset.originalLabel) {
      this.analyzeSubmitTarget.dataset.originalLabel = this.analyzeSubmitTarget.value
    }
    this.analyzeSubmitTarget.value = "Analyzing…"
  }

  endAnalyzeLoading() {
    if (!this.hasAnalyzeSubmitTarget) return
    this.analyzeSubmitTarget.disabled = false
    if (this.analyzeSubmitTarget.dataset.originalLabel) {
      this.analyzeSubmitTarget.value = this.analyzeSubmitTarget.dataset.originalLabel
    }
  }
}
