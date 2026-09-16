<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { supabase, MAIN_ROOM_ID } from './lib/supabase'

// ---------- Auth-Zustand ----------
const session = ref(null)
const profile = ref(null)
const loadingProfile = ref(false)

const isApproved = computed(() => profile.value?.status === 'approved')
const isPlatformAdmin = computed(() => profile.value?.is_platform_admin === true)

// ---------- Raum-Mitgliedschaft ----------
const membership = ref(null) // { role, status }
// Plattform-Admin hat bewusst KEIN automatisches Schreibrecht auf Rauminhalte
// (siehe konzept.md) – nur die room_admin-Rolle in genau diesem Raum zählt,
// exakt wie es die RLS-Policy "rounds: room admin write" auch prüft.
const isRoomAdmin = computed(() => membership.value?.role === 'room_admin')

// ---------- Runde + Board ----------
const round = ref(null) // aktuelle Runde (ended_at ist null) oder null
const myMarks = ref(new Set()) // Wörter, die ich selbst abgehakt habe
const otherMarks = ref(new Set()) // Wörter, die irgendwer sonst schon abgehakt hat
const reportedLines = ref(new Set()) // Linien, für die in dieser Sitzung schon report_win lief

const gridSize = computed(() => {
  const n = round.value?.words?.length || 0
  if (n >= 25) return 5
  if (n >= 16) return 4
  if (n >= 9) return 3
  return 0
})

// Deterministisch pro Runde + Spieler gemischt: alle sehen dieselben Wörter,
// aber in unterschiedlicher Reihenfolge (siehe konzept.md, "Wort-Pool zweigeteilt").
function hashSeed(str) {
  let h = 0
  for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0
  return h >>> 0
}
function mulberry32(a) {
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
function seededShuffle(arr, seed) {
  const rng = mulberry32(seed)
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

const boardWords = computed(() => {
  if (!round.value || !gridSize.value || !session.value) return []
  const cellCount = gridSize.value * gridSize.value
  const trimmed = round.value.words.slice(0, cellCount)
  const seed = hashSeed(round.value.id + session.value.user.id)
  return seededShuffle(trimmed, seed)
})

function lineIndexes(size) {
  const lines = []
  for (let r = 0; r < size; r++) lines.push([...Array(size)].map((_, c) => r * size + c))
  for (let c = 0; c < size; c++) lines.push([...Array(size)].map((_, r) => r * size + c))
  lines.push([...Array(size)].map((_, i) => i * size + i))
  lines.push([...Array(size)].map((_, i) => i * size + (size - 1 - i)))
  return lines
}

const lines = computed(() => (gridSize.value ? lineIndexes(gridSize.value) : []))

const completedLineIdxs = computed(() => {
  if (!round.value) return new Set()
  const words = boardWords.value
  const done = new Set()
  lines.value.forEach((line, idx) => {
    if (line.every((i) => myMarks.value.has(words[i]))) done.add(idx)
  })
  return done
})

// ---------- Leaderboard ----------
const leaderboard = ref([])

// ---------- UI ----------
const tab = ref('board')
const error = ref('')
// Zwischenspeicherung im Browser, damit die Wortliste eine beendete Runde
// übersteht und nicht bei jeder neuen Runde neu eingetippt werden muss.
// Ersetzt später den echten Wort-Pool (siehe konzept.md, noch offen).
const WORD_LIST_STORAGE_KEY = 'daily-bingo-main-room-word-list'
const newRoundWords = ref(localStorage.getItem(WORD_LIST_STORAGE_KEY) || '')
watch(newRoundWords, (val) => {
  try {
    localStorage.setItem(WORD_LIST_STORAGE_KEY, val)
  } catch {
    // localStorage kann in seltenen Fällen blockiert sein (privater Modus o.ä.) – dann einfach ignorieren.
  }
})
const newRoundMode = ref('first_blood')

let realtimeChannel = null

async function loadProfile(userId) {
  loadingProfile.value = true
  const { data, error: err } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle()
  if (err) error.value = 'Profil laden: ' + err.message
  profile.value = data
  loadingProfile.value = false
}

async function loadMembership(userId) {
  const { data, error: err } = await supabase
    .from('room_members')
    .select('role, status')
    .eq('room_id', MAIN_ROOM_ID)
    .eq('profile_id', userId)
    .maybeSingle()
  if (err) error.value = 'Mitgliedschaft laden: ' + err.message
  membership.value = data
}

async function loadRound() {
  const { data, error: err } = await supabase
    .from('rounds')
    .select('*')
    .eq('room_id', MAIN_ROOM_ID)
    .is('ended_at', null)
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (err) {
    error.value = 'Runde laden: ' + err.message
    return
  }
  round.value = data
  reportedLines.value = new Set()
  if (data) await loadMarks(data.id)
  else {
    myMarks.value = new Set()
    otherMarks.value = new Set()
  }
}

async function loadMarks(roundId) {
  const { data, error: err } = await supabase
    .from('marks')
    .select('word, profile_id')
    .eq('round_id', roundId)
  if (err) {
    error.value = 'Markierungen laden: ' + err.message
    return
  }
  const mine = new Set()
  const others = new Set()
  for (const m of data) {
    if (m.profile_id === session.value.user.id) mine.add(m.word)
    else others.add(m.word)
  }
  myMarks.value = mine
  otherMarks.value = others
  // Bereits bei Rundenbeginn komplette Linien nicht nochmal als "neu" werten.
  reportedLines.value = new Set(completedLineIdxs.value)
}

async function loadLeaderboard() {
  const { data, error: err } = await supabase
    .from('wins')
    .select('profile_id, lines_count, profiles ( nickname )')
    .eq('room_id', MAIN_ROOM_ID)
  if (err) {
    error.value = 'Bestenliste laden: ' + err.message
    return
  }
  const byPlayer = new Map()
  for (const w of data) {
    const key = w.profile_id
    const entry = byPlayer.get(key) || { nickname: w.profiles?.nickname || '(unbekannt)', wins: 0, lines: 0 }
    entry.wins += 1
    entry.lines += w.lines_count
    byPlayer.set(key, entry)
  }
  leaderboard.value = [...byPlayer.values()].sort((a, b) => b.wins - a.wins)
}

async function toggleWord(word) {
  if (!round.value) return
  const already = myMarks.value.has(word)
  if (already) {
    myMarks.value.delete(word)
    myMarks.value = new Set(myMarks.value)
    await supabase.from('marks').delete().eq('round_id', round.value.id).eq('word', word).eq('profile_id', session.value.user.id)
    return
  }
  myMarks.value.add(word)
  myMarks.value = new Set(myMarks.value)
  const { error: err } = await supabase
    .from('marks')
    .insert({ round_id: round.value.id, profile_id: session.value.user.id, word })
  if (err) {
    error.value = 'Markieren: ' + err.message
    return
  }
  await checkForNewBingo()
}

async function checkForNewBingo() {
  const done = completedLineIdxs.value
  const freshLines = [...done].filter((idx) => !reportedLines.value.has(idx))
  if (freshLines.length === 0) return
  freshLines.forEach((idx) => reportedLines.value.add(idx))
  const { error: err } = await supabase.rpc('report_win', {
    target_round: round.value.id,
    p_lines_count: freshLines.length,
  })
  if (err) {
    error.value = 'Bingo melden: ' + err.message
    return
  }
  await loadRound()
  await loadLeaderboard()
}

async function startNewRound() {
  const words = newRoundWords.value
    .split('\n')
    .map((w) => w.trim())
    .filter(Boolean)
  if (words.length < 9) {
    error.value = 'Mindestens 9 Wörter für ein 3×3-Board nötig.'
    return
  }
  const { error: err } = await supabase.from('rounds').insert({
    room_id: MAIN_ROOM_ID,
    mode: newRoundMode.value,
    words,
  })
  if (err) {
    error.value = 'Runde starten: ' + err.message
    return
  }
  await loadRound()
}

function subscribeRealtime(userId) {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  realtimeChannel = supabase
    .channel('room-' + MAIN_ROOM_ID)
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${MAIN_ROOM_ID}` },
      () => loadRound()
    )
    .on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'wins', filter: `room_id=eq.${MAIN_ROOM_ID}` },
      () => loadLeaderboard()
    )
    .on('postgres_changes', { event: '*', schema: 'public', table: 'marks' }, (payload) => {
      const rec = payload.new || payload.old
      if (!round.value || rec.round_id !== round.value.id) return
      if (rec.profile_id === userId) return
      loadMarks(round.value.id)
    })
    .subscribe()
}

async function bootstrapAfterLogin() {
  const user = session.value.user
  await loadProfile(user.id)
  if (!isApproved.value) return
  await loadMembership(user.id)
  await loadRound()
  await loadLeaderboard()
  subscribeRealtime(user.id)
}

async function login() {
  await supabase.auth.signInWithOAuth({ provider: 'github', options: { redirectTo: window.location.href } })
}

async function logout() {
  if (realtimeChannel) supabase.removeChannel(realtimeChannel)
  await supabase.auth.signOut()
}

onMounted(() => {
  // onAuthStateChange feuert direkt beim Registrieren einmal mit dem aktuellen
  // Session-Stand (Event INITIAL_SESSION) – ein zusätzlicher expliziter
  // getSession()-Aufruf würde bootstrapAfterLogin() doppelt auslösen.
  supabase.auth.onAuthStateChange((_event, s) => {
    const hadSession = !!session.value
    session.value = s
    if (s && !hadSession) bootstrapAfterLogin()
    else if (!s) {
      profile.value = null
      membership.value = null
      round.value = null
      if (realtimeChannel) {
        supabase.removeChannel(realtimeChannel)
        realtimeChannel = null
      }
    }
  })
})

onUnmounted(() => {
  if (realtimeChannel) supabase.removeChannel(realtimeChannel)
})
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <span class="brand">🎲 Dev Daily Bingo</span>
      <template v-if="session">
        <span class="spacer" />
        <span class="who">{{ profile?.nickname || session.user.email }}</span>
        <button class="btn ghost" @click="logout">Abmelden</button>
      </template>
    </header>

    <main class="content">
      <p v-if="error" class="error">{{ error }}</p>

      <div v-if="!session" class="center">
        <p>Anmeldung über GitHub.</p>
        <button class="btn primary" @click="login">Mit GitHub anmelden</button>
      </div>

      <div v-else-if="loadingProfile" class="center">Lade Profil…</div>

      <div v-else-if="!isApproved" class="center">
        <h2>⏳ Warte auf Freigabe</h2>
        <p>Dein Account ist angemeldet, aber noch nicht freigeschaltet. Sobald der Betreiber dich freigibt, geht's los.</p>
      </div>

      <div v-else>
        <nav class="tabs">
          <button class="tab" :class="{ active: tab === 'board' }" @click="tab = 'board'">Board</button>
          <button class="tab" :class="{ active: tab === 'rank' }" @click="tab = 'rank'">Bestenliste</button>
        </nav>

        <section v-show="tab === 'board'">
          <div v-if="!round" class="panel">
            <p>Keine laufende Runde im Hauptraum.</p>
            <div v-if="isRoomAdmin" class="new-round">
              <h3>Neue Runde starten</h3>
              <select v-model="newRoundMode">
                <option value="first_blood">First-Blood-Mode</option>
                <option value="one_week_wipe">One-Week-Wipe-Mode / Best-Of-Five-Mode</option>
              </select>
              <textarea v-model="newRoundWords" rows="10" placeholder="Ein Wort pro Zeile, mindestens 9"></textarea>
              <p class="muted small">Rastergröße richtet sich nach der Anzahl (9→3×3, 16→4×4, 25+→5×5); überzählige Wörter werden ignoriert, jeder Spieler sieht die aktiven Wörter in eigener Reihenfolge.</p>
              <button class="btn primary" @click="startNewRound">Runde starten</button>
            </div>
            <p v-else class="muted">Ein Raum-Admin muss eine neue Runde starten.</p>
          </div>

          <div v-else>
            <div class="grid" :style="{ gridTemplateColumns: `repeat(${gridSize}, 1fr)` }">
              <button
                v-for="(word, i) in boardWords"
                :key="i"
                class="cell"
                :class="{ mine: myMarks.has(word), others: otherMarks.has(word) && !myMarks.has(word) }"
                @click="toggleWord(word)"
              >
                {{ word }}
              </button>
            </div>
            <p class="legend">
              <span class="dot mine"></span> von dir markiert
              <span class="dot others"></span> von anderen im Raum schon gerufen
            </p>
          </div>
        </section>

        <section v-show="tab === 'rank'" class="panel">
          <h3>Bestenliste · Hauptraum</h3>
          <table v-if="leaderboard.length">
            <thead>
              <tr><th>Spieler</th><th>Bingos</th><th>Linien gesamt</th></tr>
            </thead>
            <tbody>
              <tr v-for="row in leaderboard" :key="row.nickname">
                <td>{{ row.nickname }}</td>
                <td>{{ row.wins }}</td>
                <td>{{ row.lines }}</td>
              </tr>
            </tbody>
          </table>
          <p v-else class="muted">Noch keine Bingos in diesem Raum.</p>
        </section>
      </div>
    </main>
  </div>
</template>

<style scoped>
.shell { max-width: 720px; margin: 0 auto; padding: 20px 16px 60px; }
.topbar { display: flex; align-items: center; gap: 12px; margin-bottom: 24px; }
.brand { font-weight: 700; font-size: 1.1rem; }
.spacer { flex: 1; }
.who { color: var(--muted); font-size: 0.85rem; }
.center { text-align: center; padding: 60px 20px; }
.error { color: var(--danger); background: rgba(243, 139, 168, 0.1); border: 1px solid var(--danger); border-radius: 8px; padding: 10px 14px; }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--border); margin-bottom: 20px; }
.tab { background: none; border: none; padding: 10px 16px; color: var(--muted); cursor: pointer; border-bottom: 2px solid transparent; }
.tab.active { color: var(--text); border-color: var(--accent); }
.panel { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 20px; }
.new-round { display: flex; flex-direction: column; gap: 10px; margin-top: 14px; }
.new-round textarea { font-family: monospace; padding: 8px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--text); }
.new-round select { padding: 8px; border-radius: 8px; border: 1px solid var(--border); background: var(--bg); color: var(--text); }
.grid { display: grid; gap: 8px; }
.cell {
  aspect-ratio: 1 / 1; border: 1px solid var(--border); border-radius: 8px;
  background: var(--card); color: var(--text); font-size: 0.8rem; padding: 6px;
  cursor: pointer; display: flex; align-items: center; justify-content: center; text-align: center;
}
.cell.mine { background: var(--accent); color: #11111b; font-weight: 600; }
.cell.others { box-shadow: inset 0 0 0 2px var(--warn); }
.legend { display: flex; gap: 16px; justify-content: center; margin-top: 14px; font-size: 0.75rem; color: var(--muted); align-items: center; }
.dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; margin-right: 4px; }
.dot.mine { background: var(--accent); }
.dot.others { background: var(--warn); }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid var(--border); }
.muted { color: var(--muted); }
.muted.small { font-size: 0.75rem; margin: 0; }
.btn { border: none; border-radius: 8px; padding: 8px 14px; cursor: pointer; font-weight: 600; }
.btn.primary { background: var(--accent); color: #11111b; }
.btn.ghost { background: transparent; border: 1px solid var(--border); color: var(--text); }
</style>
