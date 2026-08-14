/**
 * Export helpers — Excel, PNG, SVG, PPTX.
 *
 * The legacy dashboard inlined the entire pptxgenjs bundle plus a hand-rolled
 * HTML-to-Excel hack (build_v3.py:675, which wrote an .xls disguised as HTML
 * with `mso-number-format` styling). These are proper npm dependencies now,
 * loaded on demand so the initial bundle stays small.
 */

function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  // Revoke on the next tick so the click has consumed the URL
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

const stamp = () => new Date().toISOString().slice(0, 10)

/** Export an array of records to a real .xlsx workbook. */
export async function exportRowsToXlsx(
  rows: Record<string, unknown>[],
  sheetName: string,
  filename?: string,
) {
  const XLSX = await import('xlsx')
  const ws = XLSX.utils.json_to_sheet(rows)
  const wb = XLSX.utils.book_new()
  // Excel caps sheet names at 31 characters
  XLSX.utils.book_append_sheet(wb, ws, sheetName.slice(0, 31))
  const out = XLSX.write(wb, { bookType: 'xlsx', type: 'array' })
  download(
    new Blob([out], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }),
    filename ?? `${sheetName}_${stamp()}.xlsx`,
  )
}

/** Export a rendered <table> element, preserving its visible structure. */
export async function exportTableToXlsx(tableId: string, name: string) {
  const el = document.getElementById(tableId)
  if (!el) {
    console.warn(`exportTableToXlsx: no element #${tableId}`)
    return
  }
  const table = el instanceof HTMLTableElement ? el : el.querySelector('table')
  if (!table) {
    console.warn(`exportTableToXlsx: no <table> inside #${tableId}`)
    return
  }

  const XLSX = await import('xlsx')
  const wb = XLSX.utils.table_to_book(table, { raw: false })
  const out = XLSX.write(wb, { bookType: 'xlsx', type: 'array' })
  download(
    new Blob([out], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }),
    `${name}_${stamp()}.xlsx`,
  )
}

/** Serialise an inline SVG element to a downloadable .svg file. */
export function exportSvg(svg: SVGSVGElement | null, name: string) {
  if (!svg) return
  const clone = svg.cloneNode(true) as SVGSVGElement
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
  const src = new XMLSerializer().serializeToString(clone)
  download(new Blob([src], { type: 'image/svg+xml;charset=utf-8' }), `${name}_${stamp()}.svg`)
}

/** Rasterise an inline SVG to PNG at the given scale. */
export async function exportSvgAsPng(svg: SVGSVGElement | null, name: string, scale = 2) {
  if (!svg) return

  const clone = svg.cloneNode(true) as SVGSVGElement
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
  const src = new XMLSerializer().serializeToString(clone)
  const url = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(src)))}`

  const box = svg.viewBox.baseVal
  const w = (box?.width || svg.clientWidth || 560) * scale
  const h = (box?.height || svg.clientHeight || 400) * scale

  const img = new Image()
  await new Promise<void>((resolve, reject) => {
    img.onload = () => resolve()
    img.onerror = () => reject(new Error('SVG rasterisation failed'))
    img.src = url
  })

  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, w, h)
  ctx.drawImage(img, 0, 0, w, h)

  const blob = await new Promise<Blob | null>((r) => canvas.toBlob(r, 'image/png'))
  if (blob) download(blob, `${name}_${stamp()}.png`)
}

/** Export a Chart.js canvas to PNG. */
export function exportCanvasAsPng(canvas: HTMLCanvasElement | null, name: string) {
  if (!canvas) return
  // Composite onto white — Chart.js canvases are transparent
  const out = document.createElement('canvas')
  out.width = canvas.width
  out.height = canvas.height
  const ctx = out.getContext('2d')
  if (!ctx) return
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, out.width, out.height)
  ctx.drawImage(canvas, 0, 0)
  out.toBlob((blob) => { if (blob) download(blob, `${name}_${stamp()}.png`) }, 'image/png')
}

/** Build a one-slide PPTX from an image data URL. */
export async function exportImageToPptx(opts: {
  dataUrl: string
  title: string
  filename?: string
  subtitle?: string
}) {
  const { default: PptxGenJS } = await import('pptxgenjs')
  const pptx = new PptxGenJS()
  pptx.layout = 'LAYOUT_WIDE'   // 13.33 x 7.5 in

  const slide = pptx.addSlide()
  slide.addText(opts.title, {
    x: 0.5, y: 0.3, w: 12.3, h: 0.5,
    fontSize: 20, bold: true, color: '1F4E79', fontFace: 'Arial',
  })
  if (opts.subtitle) {
    slide.addText(opts.subtitle, {
      x: 0.5, y: 0.8, w: 12.3, h: 0.3,
      fontSize: 11, color: '595959', fontFace: 'Arial',
    })
  }
  slide.addImage({
    data: opts.dataUrl,
    x: 1.0, y: 1.25, w: 11.3, h: 5.7,
    sizing: { type: 'contain', w: 11.3, h: 5.7 },
  })

  await pptx.writeFile({ fileName: opts.filename ?? `${opts.title.replace(/\s+/g, '_')}_${stamp()}.pptx` })
}

/** Convert an inline SVG to a PNG data URL, for embedding in PPTX. */
export async function svgToPngDataUrl(svg: SVGSVGElement, scale = 2): Promise<string> {
  const clone = svg.cloneNode(true) as SVGSVGElement
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
  const src = new XMLSerializer().serializeToString(clone)
  const url = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(src)))}`

  const box = svg.viewBox.baseVal
  const w = (box?.width || 560) * scale
  const h = (box?.height || 400) * scale

  const img = new Image()
  await new Promise<void>((resolve, reject) => {
    img.onload = () => resolve()
    img.onerror = () => reject(new Error('SVG rasterisation failed'))
    img.src = url
  })

  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('canvas unavailable')
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, w, h)
  ctx.drawImage(img, 0, 0, w, h)
  return canvas.toDataURL('image/png')
}
