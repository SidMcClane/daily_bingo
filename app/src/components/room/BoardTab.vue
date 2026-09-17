<script setup>
import { computed } from 'vue'
import { state, boardWordsFor, linesForSize, toggleCell, gridSize, copyBoardLink } from '../../store'
import { hueFor, initials, FREE_WORD } from '../../lib/helpers'

const boardWords = computed(() => boardWordsFor())
const size = computed(() => gridSize())
const realCellCount = computed(() => boardWords.value.filter((w) => w !== FREE_WORD).length)

const myMarks = computed(
  () => new Set(state.room.marksAll.filter((m) => m.profile_id === state.profile.id).map((m) => m.word))
)

function isFilled(word) {
  return word === FREE_WORD || myMarks.value.has(word)
}

const callersByWord = computed(() => {
  const map = new Map()
  state.room.marksAll.forEach((m) => {
    if (m.profile_id === state.profile.id) return
    if (!map.has(m.word)) map.set(m.word, [])
    map.get(m.word).push(m.profile_id)
  })
  return map
})

function callerProfiles(word) {
  const ids = callersByWord.value.get(word) || []
  return ids.map((id) => state.room.members.find((m) => m.profile_id === id)?.profiles).filter(Boolean)
}

const lineCells = computed(() => {
  const words = boardWords.value
  const done = new Set()
  linesForSize().forEach((line) => {
    if (line.every((i) => isFilled(words[i]))) line.forEach((i) => done.add(i))
  })
  return done
})

const nearCells = computed(() => {
  const words = boardWords.value
  const s = new Set()
  linesForSize().forEach((line) => {
    const markedCount = line.filter((i) => isFilled(words[i])).length
    if (markedCount === size.value - 1) line.forEach((i) => { if (!isFilled(words[i])) s.add(i) })
  })
  return s
})

const myWordSet = computed(() => new Set(boardWords.value))
const calledWords = computed(() => {
  const map = new Map()
  state.room.marksAll.forEach((m) => {
    if (!map.has(m.word)) map.set(m.word, [])
    map.get(m.word).push(m.profile_id)
  })
  return [...map.entries()].map(([word, ids]) => ({
    word,
    mine: ids.includes(state.profile.id),
    callers: ids.map((id) => state.room.members.find((mm) => mm.profile_id === id)?.profiles).filter(Boolean),
  }))
})
const callsOnBoard = computed(() => calledWords.value.filter((c) => myWordSet.value.has(c.word)))
const callsOffBoard = computed(() => calledWords.value.filter((c) => !myWordSet.value.has(c.word)))

const myRoundWins = computed(() => {
  if (!state.room.round) return 0
  return state.room.wins
    .filter((w) => w.round_id === state.room.round.id && w.profile_id === state.profile.id)
    .reduce((sum, w) => sum + w.lines_count, 0)
})

function markCount(profileId) {
  return state.room.marksAll.filter((m) => m.profile_id === profileId).length
}

const membersByProgress = computed(() => [...state.room.members].sort((a, b) => markCount(b.profile_id) - markCount(a.profile_id)))

const boardLocked = computed(() => !!state.room.round?.ended_at)
</script>

<template>
  <div>
    <div v-if="!state.room.round" class="panel">
      <p>Keine laufende Runde in diesem Raum.</p>
      <p class="muted" style="font-size:.84rem;color:var(--faint)">
        Ein Raum-Admin kann im Tab „Raum-Admin" eine neue Runde starten.
      </p>
    </div>

    <div v-else>
      <div class="roundstrip">
        <div class="stat">
          <span class="stat-label">Markiert</span>
          <span class="stat-value">{{ myMarks.size }}<span style="color:var(--faint)">/{{ realCellCount }}</span></span>
        </div>
        <div class="stat">
          <span class="stat-label">Fast voll</span>
          <span class="stat-value" :class="{ warn: nearCells.size > 0 }">{{ Math.round(nearCells.size / Math.max(1, size - 1)) }} Linien</span>
        </div>
        <div class="stat">
          <span class="stat-label">Deine Bingos</span>
          <span class="stat-value accent">{{ myRoundWins }}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Gerufen</span>
          <span class="stat-value" style="color:var(--peach)">{{ calledWords.length }}</span>
        </div>
        <div class="grow">
          <button class="btn btn-sm" @click="copyBoardLink">Board-Link kopieren</button>
        </div>
      </div>

      <div class="layout">
        <div class="board-wrap">
          <div class="lockbar" v-if="boardLocked">🎯 Bingo! Runde beendet – warte auf eine neue Runde.</div>

          <div class="board" :class="{ locked: boardLocked }" :style="{ gridTemplateColumns: `repeat(${size}, 1fr)` }">
            <button
              v-for="(word, i) in boardWords"
              :key="i"
              class="cell"
              :class="{
                'is-free': word === FREE_WORD,
                'is-marked': myMarks.has(word),
                'in-line': lineCells.has(i),
                'is-next': !isFilled(word) && nearCells.has(i),
                'is-called': !isFilled(word) && callerProfiles(word).length > 0,
              }"
              :disabled="boardLocked || word === FREE_WORD"
              @click="toggleCell(word)"
            >
              {{ word }}
              <span class="callers" v-if="!isFilled(word) && callerProfiles(word).length">
                <i class="caller-dot" v-for="(p, pi) in callerProfiles(word).slice(0, 3)" :key="pi" :style="{ background: hueFor(p) }"></i>
              </span>
            </button>
          </div>

          <div class="legend">
            <span><i class="swatch" style="background:color-mix(in srgb,var(--green) 16%,var(--surface));border-color:var(--green)"></i> selbst abgehakt</span>
            <span><i class="caller-dot" style="background:var(--peach)"></i> von anderen gerufen</span>
            <span><i class="swatch" style="background:transparent;border-color:var(--blue);border-style:dashed"></i> fehlt für Bingo</span>
            <span><i class="swatch" style="background:color-mix(in srgb,var(--yellow) 18%,var(--surface));border-color:var(--yellow)"></i> Gewinnlinie</span>
          </div>
        </div>

        <div class="stack">
          <div class="panel">
            <div class="panel-head">
              <span class="panel-title">Gerufene Wörter</span>
              <span class="chip mono">{{ calledWords.length }}</span>
            </div>
            <div class="calls" v-if="calledWords.length">
              <div class="calls-group">Auf deinem Board · {{ callsOnBoard.length }}</div>
              <div v-for="c in callsOnBoard" :key="'on' + c.word" class="call-row" :class="c.mine ? 'mine' : 'todo'">
                <span class="call-word">{{ c.word }}<small>{{ c.mine ? 'von dir abgehakt' : 'noch offen' }}</small></span>
                <span class="call-dots">
                  <i class="caller-dot" v-for="(p, pi) in c.callers.slice(0, 3)" :key="pi" :style="{ background: hueFor(p) }"></i>
                </span>
              </div>
              <template v-if="callsOffBoard.length">
                <div class="calls-group">Nicht auf deinem Board · {{ callsOffBoard.length }}</div>
                <div v-for="c in callsOffBoard" :key="'off' + c.word" class="call-row foreign">
                  <span class="call-word">{{ c.word }}</span>
                  <span class="call-dots">
                    <i class="caller-dot" v-for="(p, pi) in c.callers.slice(0, 3)" :key="pi" :style="{ background: hueFor(p) }"></i>
                  </span>
                </div>
              </template>
            </div>
            <p v-else style="margin:0;font-size:.82rem;color:var(--faint)">In dieser Runde wurde noch nichts gerufen.</p>
            <p class="note" style="margin-top:12px">
              Bewusst ohne Sammel-Button: Nachtragen bleibt Einzelklick.
            </p>
          </div>

          <div class="panel">
            <div class="panel-head">
              <span class="panel-title">Am Board</span>
              <span class="chip"><span class="chip-dot"></span>{{ state.room.onlineIds.size }} online</span>
            </div>
            <div class="players">
              <div v-for="p in membersByProgress" :key="p.profile_id" class="player-row">
                <span
                  class="avatar"
                  :style="{ background: state.room.onlineIds.has(p.profile_id) ? hueFor(p.profiles) : 'var(--surface-3)', color: state.room.onlineIds.has(p.profile_id) ? 'var(--mantle)' : 'var(--faint)' }"
                >{{ initials(p.profiles?.nickname) }}</span>
                <span class="player-name">
                  {{ p.profiles?.nickname }}<span v-if="p.profile_id === state.profile.id" style="color:var(--faint)"> (du)</span>
                  <span v-if="!state.room.onlineIds.has(p.profile_id)" class="offline"> · weg</span>
                </span>
                <span class="player-meta">{{ markCount(p.profile_id) }}/{{ realCellCount }}</span>
                <span class="bar">
                  <i :style="{ width: (markCount(p.profile_id) / Math.max(1, realCellCount) * 100) + '%', background: hueFor(p.profiles) }"></i>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
