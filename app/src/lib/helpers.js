export const HUES = ['#89b4fa', '#f38ba8', '#a6e3a1', '#cba6f7', '#fab387', '#94e2d5', '#f5c2e7', '#eba0ac']

export function hueFor(profile) {
  if (profile?.color) return profile.color
  const id = profile?.id || ''
  let h = 0
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0
  return HUES[Math.abs(h) % HUES.length]
}

export function initials(name) {
  return (name || '?').trim().charAt(0).toUpperCase()
}

export function modeLabel(m) {
  return m === 'first_blood' ? 'First-Blood' : 'One-Week-Wipe / Best-Of-Five'
}

export function visLabel(v) {
  return v === 'open' ? 'offen' : v === 'protected' ? 'geschützt' : 'nicht gelistet'
}

export function cellLenClass(t) {
  const l = (t || '').length
  return l > 44 ? 'len-xl' : l > 26 ? 'len-l' : ''
}

export function hashSeed(str) {
  let h = 0
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0
  return h >>> 0
}

export function mulberry32(a) {
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

export function seededShuffle(arr, seed) {
  const rng = mulberry32(seed)
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export function gridSizeFor(n) {
  if (n >= 25) return 5
  if (n >= 16) return 4
  if (n >= 9) return 3
  return 0
}

export function lineIndexes(size) {
  const lines = []
  for (let r = 0; r < size; r++) lines.push([...Array(size)].map((_, c) => r * size + c))
  for (let c = 0; c < size; c++) lines.push([...Array(size)].map((_, r) => r * size + c))
  lines.push([...Array(size)].map((_, i) => i * size + i))
  lines.push([...Array(size)].map((_, i) => i * size + (size - 1 - i)))
  return lines
}

const DAY = 86400000
const pad2 = (n) => String(n).padStart(2, '0')
export function dayKey(d) {
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate())
}
export { DAY }
