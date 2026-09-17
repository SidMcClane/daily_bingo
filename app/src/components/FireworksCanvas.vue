<script setup>
import { watch, onMounted, onUnmounted } from 'vue'
import { state } from '../store'

let canvas = null
let ctx = null
let particles = []
let animating = false
let pending = 0

function sizeCanvas() {
  if (!canvas) return
  canvas.width = window.innerWidth
  canvas.height = window.innerHeight
}

function burst(x, y) {
  const colors = ['#f9e2af', '#a6e3a1', '#89b4fa', '#f38ba8', '#cba6f7', '#fab387']
  const color = colors[Math.floor(Math.random() * colors.length)]
  for (let i = 0; i < 48; i++) {
    const a = (Math.PI * 2 * i) / 48 + Math.random() * 0.3
    const s = 2 + Math.random() * 3.6
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, alpha: 1, color, size: 2 + Math.random() * 2 })
  }
}

function frame() {
  if (!ctx) return
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  particles.forEach((p) => {
    p.x += p.vx
    p.y += p.vy
    p.vy += 0.055
    p.vx *= 0.99
    p.alpha -= 0.0115
  })
  particles = particles.filter((p) => p.alpha > 0)
  particles.forEach((p) => {
    ctx.globalAlpha = Math.max(p.alpha, 0)
    ctx.fillStyle = p.color
    ctx.beginPath()
    ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2)
    ctx.fill()
  })
  ctx.globalAlpha = 1
  if (pending > 0 || particles.length) requestAnimationFrame(frame)
  else animating = false
}

function fireworks() {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  if (reduced || !ctx) return
  pending += 7
  for (let i = 0; i < 7; i++) {
    setTimeout(() => {
      burst(canvas.width * (0.12 + Math.random() * 0.76), canvas.height * (0.12 + Math.random() * 0.42))
      pending--
    }, i * 300)
  }
  if (!animating) {
    animating = true
    requestAnimationFrame(frame)
  }
}

onMounted(() => {
  canvas = document.getElementById('fw')
  ctx = canvas.getContext('2d')
  sizeCanvas()
  window.addEventListener('resize', sizeCanvas)
})
onUnmounted(() => window.removeEventListener('resize', sizeCanvas))

watch(
  () => state.fireworksTrigger,
  (v) => { if (v) fireworks() }
)
</script>

<template>
  <canvas id="fw"></canvas>
</template>
