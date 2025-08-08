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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Monaco Editor Hook
let MonacoEditor = {
  mounted() {
    // Load Monaco Editor
    this.loadMonaco().then(() => {
      this.initEditor()
    })
  },

  loadMonaco() {
    if (window.monaco) {
      return Promise.resolve()
    }

    return new Promise((resolve) => {
      const script = document.createElement('script')
      script.src = 'https://unpkg.com/monaco-editor@latest/min/vs/loader.js'
      script.onload = () => {
        window.require.config({ 
          paths: { 
            vs: 'https://unpkg.com/monaco-editor@latest/min/vs' 
          } 
        })
        window.require(['vs/editor/editor.main'], () => {
          resolve()
        })
      }
      document.head.appendChild(script)
    })
  },

  initEditor() {
    const container = this.el
    const language = container.dataset.language || 'javascript'
    const theme = container.dataset.theme || 'vs-dark'
    const value = container.dataset.value || ''

    this.editor = window.monaco.editor.create(container, {
      value: value,
      language: language,
      theme: theme,
      minimap: { enabled: false },
      automaticLayout: true,
      fontSize: 14,
      wordWrap: 'on'
    })

    // Send changes to LiveView
    this.editor.onDidChangeModelContent(() => {
      const value = this.editor.getValue()
      this.pushEvent("code_change", {value: value})
    })

    // Listen for external updates
    this.handleEvent("update_code", ({code}) => {
      if (this.editor.getValue() !== code) {
        this.editor.setValue(code)
      }
    })

    // Apply agent suggestions
    this.handleEvent("apply_suggestion", ({suggestion}) => {
      // Apply the suggestion to the editor
      const currentCode = this.editor.getValue()
      // Simple replace for demo - in production would be more sophisticated
      this.editor.setValue(suggestion.code || currentCode)
    })
  },

  destroyed() {
    if (this.editor) {
      this.editor.dispose()
    }
  }
}

// Resize Handle Hook
let ResizeHandle = {
  mounted() {
    let isResizing = false
    let startX = 0
    let startWidths = {}

    this.el.addEventListener('mousedown', (e) => {
      isResizing = true
      startX = e.clientX
      
      const editor = this.el.previousElementSibling
      const chat = this.el.nextElementSibling
      const container = this.el.parentElement
      
      startWidths = {
        editor: editor.offsetWidth,
        chat: chat.offsetWidth,
        container: container.offsetWidth
      }
      
      document.body.style.cursor = 'col-resize'
      e.preventDefault()
    })

    document.addEventListener('mousemove', (e) => {
      if (!isResizing) return
      
      const deltaX = e.clientX - startX
      const newEditorWidth = startWidths.editor + deltaX
      const editorPercent = Math.round((newEditorWidth / startWidths.container) * 100)
      
      // Constrain between 30% and 85%
      const constrainedPercent = Math.max(30, Math.min(85, editorPercent))
      
      this.pushEvent("update_layout", {width: constrainedPercent.toString()})
    })

    document.addEventListener('mouseup', () => {
      if (isResizing) {
        isResizing = false
        document.body.style.cursor = ''
      }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {MonacoEditor, ResizeHandle}
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