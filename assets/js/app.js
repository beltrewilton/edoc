// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/edoc"
import jsonFormatHighlight from "../vendor/json-format-highlight"
import topbar from "../vendor/topbar"

document.addEventListener("edoc:modal-open", (event) => {
  const dialog = event.target

  if (!(dialog instanceof HTMLDialogElement)) {
    return
  }

  if (typeof dialog.showModal === "function") {
    if (!dialog.open) {
      dialog.showModal()
    }

    return
  }

  dialog.setAttribute("open", "true")
})

document.addEventListener("edoc:modal-close", (event) => {
  const dialog = event.target

  if (!(dialog instanceof HTMLDialogElement)) {
    return
  }

  if (typeof dialog.close === "function") {
    if (dialog.open) {
      dialog.close()
    }

    return
  }

  dialog.removeAttribute("open")
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const RawJsonViewer = {
  mounted() {
    this.copyButton = this.el.querySelector("[data-role='copy-json']")
    this.copyFeedback = this.el.querySelector("[data-role='copy-feedback']")
    this.jsonTarget = this.el.querySelector("[data-role='json-highlight']")
    this.copyTimeout = null
    this.copyPayload = ""
    this.copyListener = () => this.copyRawJson()

    if (this.copyButton) {
      this.copyButton.addEventListener("click", this.copyListener)
    }

    this.renderJson()
  },
  updated() {
    this.renderJson()
  },
  destroyed() {
    if (this.copyButton) {
      this.copyButton.removeEventListener("click", this.copyListener)
    }

    if (this.copyTimeout) {
      clearTimeout(this.copyTimeout)
    }
  },
  renderJson() {
    const rawJson = this.el.dataset.json || ""
    let highlightedJson

    try {
      const parsedJson = JSON.parse(rawJson)

      highlightedJson = jsonFormatHighlight(parsedJson, {
        keyColor: "#93c5fd",
        numberColor: "#facc15",
        stringColor: "#86efac",
        trueColor: "#5eead4",
        falseColor: "#fda4af",
        nullColor: "#f9a8d4",
      })
      this.copyPayload = JSON.stringify(parsedJson, null, 2)
    } catch (_error) {
      const fallbackJson = rawJson.trim() === "" ? "No payload available." : rawJson

      highlightedJson = this.escapeHtml(fallbackJson)
      this.copyPayload = fallbackJson
    }

    if (this.jsonTarget) {
      this.jsonTarget.innerHTML = highlightedJson
    }
  },
  async copyRawJson() {
    if (!this.copyPayload) {
      return
    }

    if (!navigator.clipboard) {
      this.showCopyFeedback("Clipboard unavailable")
      return
    }

    try {
      await navigator.clipboard.writeText(this.copyPayload)
      this.showCopyFeedback("Copied")
    } catch (_error) {
      this.showCopyFeedback("Copy failed")
    }
  },
  showCopyFeedback(message) {
    if (!this.copyFeedback) {
      return
    }

    this.copyFeedback.textContent = message
    this.copyFeedback.classList.remove("opacity-0")
    this.copyFeedback.classList.add("opacity-100")

    if (this.copyTimeout) {
      clearTimeout(this.copyTimeout)
    }

    this.copyTimeout = setTimeout(() => {
      this.copyFeedback.classList.remove("opacity-100")
      this.copyFeedback.classList.add("opacity-0")
    }, 1400)
  },
  escapeHtml(value) {
    return value
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  },
}

const hooks = {
  ...colocatedHooks,
  RawJsonViewer,
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
