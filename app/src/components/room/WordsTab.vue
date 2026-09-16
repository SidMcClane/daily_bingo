<script setup>
import { ref, computed } from 'vue'
import { state, proposeWord, toggleVote, votesFor, isRoomAdmin, approveWord, rejectWord } from '../../store'

const wordFilter = ref('all')

const activeWords = computed(() => state.room.wordPool.filter((w) => w.status === 'active'))
const coldWords = computed(() => activeWords.value.filter((w) => !state.room.wordHitCounts[w.word]).slice(0, 8))

const filteredWords = computed(() => {
  let list = state.room.wordPool
  if (wordFilter.value === 'active') list = list.filter((w) => w.status === 'active')
  else if (wordFilter.value === 'proposed') list = list.filter((w) => w.status === 'proposed')
  else if (wordFilter.value === 'cold') list = list.filter((w) => w.status === 'active' && !state.room.wordHitCounts[w.word])
  return [...list].sort((a, b) => votesFor(b.id) - votesFor(a.id))
})

function hitsFor(word) {
  return state.room.wordHitCounts[word] || 0
}
</script>

<template>
  <div class="layout">
    <div class="stack">
      <div class="panel">
        <div class="panel-head">
          <span class="panel-title">Pool · {{ state.room.data?.name }}</span>
          <div class="seg">
            <button :aria-pressed="wordFilter === 'all'" @click="wordFilter = 'all'">Alle</button>
            <button :aria-pressed="wordFilter === 'active'" @click="wordFilter = 'active'">Aktiv</button>
            <button :aria-pressed="wordFilter === 'proposed'" @click="wordFilter = 'proposed'">Neu</button>
            <button :aria-pressed="wordFilter === 'cold'" @click="wordFilter = 'cold'">Nie gerufen</button>
          </div>
        </div>

        <form @submit.prevent="proposeWord" style="display:flex;gap:8px;margin-bottom:14px">
          <input type="text" v-model="state.room.newWord" placeholder="Eigenes Wort vorschlagen …" maxlength="60">
          <button class="btn btn-primary" type="submit" :disabled="!state.room.newWord.trim()">Vorschlagen</button>
        </form>

        <div class="words">
          <div v-for="w in filteredWords" :key="w.id" class="word-row">
            <span class="word-text">
              {{ w.word }}
              <small v-if="w.status === 'proposed'">wartet auf Freigabe</small>
            </span>
            <span class="hits" :title="hitsFor(w.word) + ' Treffer insgesamt'">
              <span class="hits-bar"><i :style="{ width: Math.min(100, hitsFor(w.word) * 10) + '%' }"></i></span>
              <span class="hits-num" :class="{ cold: hitsFor(w.word) === 0 }">{{ hitsFor(w.word) }}×</span>
            </span>
            <span class="word-votes">{{ votesFor(w.id) }}</span>
            <span style="display:flex;gap:6px">
              <button class="btn btn-sm votebtn" :class="{ voted: state.room.wordVotesMine.has(w.id) }" @click="toggleVote(w)">
                {{ state.room.wordVotesMine.has(w.id) ? '▲ gevotet' : '▲ Vote' }}
              </button>
              <template v-if="isRoomAdmin() && w.status === 'proposed'">
                <button class="btn btn-sm btn-primary" @click="approveWord(w)">Freigeben</button>
                <button class="btn btn-sm btn-danger" @click="rejectWord(w)">Ablehnen</button>
              </template>
            </span>
          </div>
          <p v-if="!filteredWords.length" style="margin:0;font-size:.84rem;color:var(--faint)">Keine Wörter in diesem Filter.</p>
        </div>
      </div>
    </div>

    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Top-Votes-Anteil für die nächste Runde</span></div>
        <div class="field" style="margin-bottom:10px">
          <span class="field-label">Top-Votes im Board · {{ state.room.topCount }}</span>
          <input type="range" min="0" max="25" v-model.number="state.room.topCount">
        </div>
        <div class="mix" style="margin-bottom:10px">
          <div class="top" :style="{ width: (state.room.topCount / 25 * 100) + '%' }"></div>
          <div class="rand" :style="{ width: ((25 - state.room.topCount) / 25 * 100) + '%' }"></div>
        </div>
        <p style="margin:0 0 10px;font-size:.82rem;color:var(--subtext)">
          <b style="color:var(--mauve)">{{ state.room.topCount }}</b> meistgevotete Wörter,
          <b style="color:var(--blue)">{{ Math.max(0, 25 - state.room.topCount) }}</b> zufällig aus dem Rest. Wird beim nächsten
          Rundenstart im Tab „Raum-Admin" verwendet.
        </p>
        <p class="note">
          Die Trefferquote macht das Voting fundierter – aber auch gleichförmiger, wenn immer dieselben Dauerbrenner gewinnen.
        </p>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Nie gerufen · Kandidaten zum Aussortieren</span></div>
        <div class="lb" v-if="coldWords.length">
          <div v-for="w in coldWords" :key="w.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto; padding:7px 6px">
            <span class="word-text" style="font-size:.8rem;color:var(--muted)">{{ w.word }}</span>
            <span class="hits-num cold">0×</span>
          </div>
        </div>
        <p v-else style="margin:0;font-size:.82rem;color:var(--faint)">Jedes aktive Wort ist mindestens einmal gefallen.</p>
      </div>
    </div>
  </div>
</template>
