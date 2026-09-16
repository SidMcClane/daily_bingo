<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { state, updateNickname, updateColor, leaveRoom, cancelJoinRequest, roleIn, logout, loadLobby } from '../store'
import { HUES, hueFor, initials } from '../lib/helpers'
import { supabase } from '../lib/supabase'

const nickname = ref(state.profile?.nickname || '')
const myTotalWins = ref(0)
const myWeekWins = ref(0)

watch(() => state.profile?.nickname, (v) => { nickname.value = v || '' })

const myRooms = computed(() => state.myMemberships.filter((m) => m.status === 'active').map((m) => m.rooms))
const pendingRequests = computed(() => state.myMemberships.filter((m) => m.status === 'pending').map((m) => m.rooms))

async function loadStats() {
  const { data } = await supabase.from('wins').select('lines_count, achieved_at').eq('profile_id', state.profile.id)
  if (!data) return
  myTotalWins.value = data.reduce((sum, w) => sum + w.lines_count, 0)
  const weekAgo = Date.now() - 7 * 86400000
  myWeekWins.value = data
    .filter((w) => new Date(w.achieved_at).getTime() >= weekAgo)
    .reduce((sum, w) => sum + w.lines_count, 0)
}

onMounted(() => {
  loadLobby()
  loadStats()
})

function saveNickname() {
  const v = nickname.value.trim()
  if (v && v !== state.profile.nickname) updateNickname(v)
}
</script>

<template>
  <div class="layout">
    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Profil</span></div>
        <div style="display:flex;gap:14px;align-items:center;margin-bottom:16px">
          <span class="avatar lg" :style="{ background: hueFor(state.profile) }">{{ initials(state.profile?.nickname) }}</span>
          <div>
            <div style="font-weight:700;font-size:1.05rem">{{ state.profile?.nickname }}</div>
          </div>
        </div>
        <div class="field" style="margin-bottom:14px">
          <label class="field-label" for="nickname">Anzeigename</label>
          <input type="text" id="nickname" v-model="nickname" maxlength="30" @blur="saveNickname" @keyup.enter="saveNickname">
        </div>
        <div class="field">
          <span class="field-label">Farbe</span>
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button
              v-for="c in HUES"
              :key="c"
              class="avatar lg"
              :style="{ background: c, outline: state.profile?.color === c ? '2px solid var(--text)' : 'none', outlineOffset: '2px', border: 0, cursor: 'pointer' }"
              @click="updateColor(c)"
            >{{ initials(state.profile?.nickname) }}</button>
          </div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Meine Mitgliedschaften</span></div>
        <div class="lb">
          <div v-for="r in myRooms" :key="r.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto auto">
            <span class="player-name">{{ r.name }}</span>
            <span class="tag" :class="roleIn(r.id) === 'room_admin' ? 'active' : ''">
              {{ roleIn(r.id) === 'room_admin' ? 'Raum-Admin' : 'Mitglied' }}
            </span>
            <button class="btn btn-sm btn-danger" @click="leaveRoom(r.id)">Austreten</button>
          </div>
          <div v-for="r in pendingRequests" :key="'p' + r.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto auto">
            <span class="player-name">{{ r.name }}</span>
            <span class="tag proposed">angefragt</span>
            <button class="btn btn-sm" @click="cancelJoinRequest(r.id)">Zurückziehen</button>
          </div>
          <p v-if="!myRooms.length && !pendingRequests.length" class="muted" style="font-size:.84rem;color:var(--faint)">
            Noch in keinem Raum.
          </p>
        </div>
      </div>
    </div>

    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Bilanz über alle Räume</span></div>
        <div class="kpis">
          <div class="kpi"><div class="kpi-value" style="color:var(--yellow)">{{ myTotalWins }}</div><div class="kpi-label">Bingos gesamt</div></div>
          <div class="kpi"><div class="kpi-value" style="color:var(--green)">{{ myWeekWins }}</div><div class="kpi-label">diese Woche</div></div>
          <div class="kpi"><div class="kpi-value">{{ myRooms.length }}</div><div class="kpi-label">Räume</div></div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Sitzung</span></div>
        <button class="btn btn-block btn-sm" @click="logout">Abmelden</button>
      </div>
    </div>
  </div>
</template>
