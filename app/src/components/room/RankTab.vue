<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { state, dayKey, DAY } from '../../store'
import { supabase } from '../../lib/supabase'
import { hueFor, initials, modeLabel } from '../../lib/helpers'

const lbRange = ref('week')
const recentRounds = ref([])

async function loadRecentRounds() {
  const { data } = await supabase
    .from('rounds')
    .select('id, mode, started_at, ended_at')
    .eq('room_id', state.room.id)
    .order('started_at', { ascending: false })
    .limit(6)
  const rounds = data || []
  const withWinners = await Promise.all(
    rounds.map(async (r) => {
      if (!r.ended_at) return { ...r, winnerName: null }
      const win = state.room.wins.find((w) => w.round_id === r.id)
      return { ...r, winnerName: win?.profiles?.nickname || null }
    })
  )
  recentRounds.value = withWinners
}

onMounted(loadRecentRounds)
watch(() => state.room.wins, loadRecentRounds)

const weekAgo = () => Date.now() - 7 * DAY

const leaderboard = computed(() => {
  const since = lbRange.value === 'week' ? weekAgo() : 0
  return state.room.members
    .map((m) => {
      const rows = state.room.wins.filter((w) => w.profile_id === m.profile_id && new Date(w.achieved_at).getTime() >= since)
      return {
        id: m.profile_id,
        nickname: m.profiles?.nickname,
        color: m.profiles?.color,
        wins: rows.reduce((s, w) => s + w.lines_count, 0),
        streak: streakFor(m.profile_id),
      }
    })
    .sort((a, b) => b.wins - a.wins || b.streak - a.streak)
})

function streakFor(profileId) {
  const days = new Set(state.room.wins.filter((w) => w.profile_id === profileId).map((w) => dayKey(new Date(w.achieved_at))))
  let best = 0
  let run = 0
  for (let d = 40; d >= 0; d--) {
    if (days.has(dayKey(new Date(Date.now() - d * DAY)))) { run++; best = Math.max(best, run) }
    else run = 0
  }
  return best
}

const myRoomWins = computed(() => leaderboard.value.find((r) => r.id === state.profile.id)?.wins || 0)
const myStreak = computed(() => streakFor(state.profile.id))

const weekdays = ['M', 'D', 'M', 'D', 'F', 'S', 'S']
const calendar = computed(() => {
  const out = []
  const today = new Date()
  const offset = (today.getDay() + 6) % 7
  const start = new Date(today.getTime() - (offset + 28) * DAY)
  for (let i = 0; i < 35; i++) {
    const d = new Date(start.getTime() + i * DAY)
    const key = dayKey(d)
    const count = state.room.wins.filter((w) => dayKey(new Date(w.achieved_at)) === key).length
    out.push({
      key,
      level: count === 0 ? '' : count === 1 ? 'l1' : count === 2 ? 'l2' : 'l3',
      isToday: key === dayKey(today),
      label: d.toLocaleDateString('de-DE') + ' · ' + count + ' Bingo' + (count === 1 ? '' : 's'),
    })
  }
  return out
})
</script>

<template>
  <div class="layout">
    <div class="stack">
      <div class="panel">
        <div class="panel-head">
          <span class="panel-title">Bestenliste · {{ state.room.data?.name }}</span>
          <div class="seg">
            <button :aria-pressed="lbRange === 'week'" @click="lbRange = 'week'">Woche</button>
            <button :aria-pressed="lbRange === 'all'" @click="lbRange = 'all'">Gesamt</button>
          </div>
        </div>
        <div class="lb">
          <div class="lb-row lb-head">
            <span></span><span></span><span>Spieler</span><span class="lb-num">Bingos</span><span class="lb-num">Serie</span>
          </div>
          <div v-for="(row, idx) in leaderboard" :key="row.id" class="lb-row" :class="{ 'is-me': row.id === state.profile.id }" style="grid-template-columns:26px 30px minmax(0,1fr) auto auto">
            <span class="lb-rank" :class="{ top: idx === 0 && row.wins > 0 }">{{ idx === 0 && row.wins > 0 ? '🏆' : '#' + (idx + 1) }}</span>
            <span class="avatar" :style="{ background: hueFor({ id: row.id, color: row.color }) }">{{ initials(row.nickname) }}</span>
            <span class="player-name">{{ row.nickname }}</span>
            <span class="lb-num big">{{ row.wins }}</span>
            <span class="lb-num" style="color:var(--peach)">{{ row.streak }}</span>
          </div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Letzte Runden</span></div>
        <div class="lb">
          <div v-for="r in recentRounds" :key="r.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto">
            <span class="player-name">{{ r.winnerName ? r.winnerName + ' gewinnt' : 'läuft noch' }}</span>
            <span class="tag" :class="r.mode === 'first_blood' ? 'proposed' : 'active'">{{ modeLabel(r.mode) }}</span>
          </div>
          <p v-if="!recentRounds.length" style="margin:0;font-size:.84rem;color:var(--faint)">Noch keine Runden.</p>
        </div>
      </div>
    </div>

    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Deine Bilanz hier</span></div>
        <div class="kpis">
          <div class="kpi"><div class="kpi-value" style="color:var(--yellow)">{{ myRoomWins }}</div><div class="kpi-label">Bingos</div></div>
          <div class="kpi"><div class="kpi-value">{{ myStreak }}</div><div class="kpi-label">längste Serie</div></div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head">
          <span class="panel-title">Sieg-Kalender</span>
          <span class="mono" style="font-size:.66rem;color:var(--faint)">letzte 5 Wochen</span>
        </div>
        <div class="cal" style="margin-bottom:6px">
          <span v-for="(d, i) in weekdays" :key="'wd' + i" class="cal-label">{{ d }}</span>
        </div>
        <div class="cal">
          <div v-for="day in calendar" :key="day.key" class="cal-cell" :class="[day.level, { today: day.isToday }]" :title="day.label"></div>
        </div>
      </div>
    </div>
  </div>
</template>
