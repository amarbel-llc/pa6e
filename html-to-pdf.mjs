#!/usr/bin/env zx
import { spawn } from 'node:child_process'

const target = argv._[0]
const options = argv._[1]
const bufferSize = argv._[2] || '9999999'

if (!target || !options) {
  console.error('Usage: html-to-pdf <file.html> \'<CDP options>\'')
  process.exit(1)
}

// Find Chrome
const isMac = os.platform() === 'darwin'
const chromePath = isMac
  ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  : which.sync('chromium')

if (!fs.existsSync(chromePath)) {
  console.error(`error: Chrome not found at ${chromePath}`)
  process.exit(1)
}

const absTarget = path.resolve(target)
const outfile = `${target}.pdf`

// Launch Chrome with auto-allocated port
const chromeProc = spawn(chromePath, [
  '--no-sandbox', '--headless', '--remote-debugging-port=0',
  '--remote-allow-origins=*', absTarget,
], { stdio: ['ignore', 'pipe', 'pipe'] })

// Read stderr to find the DevTools port
const host = await new Promise((resolve, reject) => {
  let buf = ''
  const timeout = setTimeout(() => reject(new Error('Chrome startup timed out')), 10000)
  chromeProc.stderr.on('data', (chunk) => {
    buf += chunk.toString()
    const match = buf.match(/DevTools listening on ws:\/\/([^/]+)/)
    if (match) {
      clearTimeout(timeout)
      resolve(match[1])
    }
  })
  chromeProc.on('exit', () => {
    clearTimeout(timeout)
    reject(new Error('Chrome exited before DevTools was ready'))
  })
})

try {
  // Get the page's websocket URL
  const listResp = await fetch(`http://${host}/json/list`)
  const pages = await listResp.json()
  const page = pages.find(p => p.type === 'page')

  if (!page) {
    console.error('error: no page found in Chrome')
    process.exit(1)
  }

  console.error(`Requesting print from ${page.webSocketDebuggerUrl}`)

  // Connect via websocket and request PDF
  const ws = new WebSocket(page.webSocketDebuggerUrl)

  const pdfData = await new Promise((resolve, reject) => {
    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Page.printToPDF',
        params: JSON.parse(`{ ${options} }`)
      }))
    }
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data)
      if (msg.id === 1) {
        if (msg.error) reject(new Error(msg.error.message))
        else resolve(msg.result.data)
      }
    }
    ws.onerror = reject
  })

  // Decode base64 and write
  fs.writeFileSync(outfile, Buffer.from(pdfData, 'base64'))
  console.error(`Wrote PDF to '${outfile}'`)

} finally {
  chromeProc.kill('SIGKILL')
}
