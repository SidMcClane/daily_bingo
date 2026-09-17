<script setup>
import { ref, watch } from 'vue'
import {
  state,
  approveMember,
  denyMember,
  kickMember,
  banMember,
  unbanMember,
  bulkAddWords,
  startNewRoundFromPool,
  updateRoomSettings,
  toggleFreeSpace,
} from '../../store'
import { hueFor, initials } from '../../lib/helpers'

const newRoundMode = ref('first_blood')
const roomName = ref(state.room.data?.name || '')
const roomVisibility = ref(state.room.data?.visibility || 'open')
const roomCode = ref(state.room.data?.join_code || '')

watch(
  () => state.room.data,
  (d) => {
    if (!d) return
    roomName.value = d.name
    roomVisibility.value = d.visibility
    roomCode.value = d.join_code || ''
  }
)

function saveRoomSettings() {
  updateRoomSettings(roomName.value, roomVisibility.value, roomCode.value)
}
</script>

<template>
  <div class="layout">
    <div class="stack">
      <div class="panel">
        <div class="panel-head">
          <span class="panel-title">Beitrittsanfragen</span>
          <span class="chip" v-if="state.room.joinRequests.length">{{ state.room.joinRequests.length }} offen</span>
        </div>
        <div class="lb" v-if="state.room.joinRequests.length">
          <div v-for="m in state.room.joinRequests" :key="m.profile_id" class="lb-row" style="grid-template-columns:30px minmax(0,1fr) auto">
            <span class="avatar" :style="{ background: hueFor(m.profiles) }">{{ initials(m.profiles?.nickname) }}</span>
            <span class="player-name">{{ m.profiles?.nickname }}</span>
            <span style="display:flex;gap:6px">
              <button class="btn btn-sm btn-primary" @click="approveMember(m)">Aufnehmen</button>
              <button class="btn btn-sm btn-danger" @click="denyMember(m)">Ablehnen</button>
            </span>
          </div>
        </div>
        <p v-else style="margin:0;font-size:.84rem;color:var(--faint)">Keine offenen Anfragen.</p>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Mitglieder</span></div>
        <div class="lb">
          <div v-for="p in state.room.members" :key="p.profile_id" class="lb-row" style="grid-template-columns:30px minmax(0,1fr) auto auto">
            <span class="avatar" :style="{ background: hueFor(p.profiles) }">{{ initials(p.profiles?.nickname) }}</span>
            <span class="player-name">{{ p.profiles?.nickname }}</span>
            <span class="tag" :class="p.role === 'room_admin' ? 'active' : ''">{{ p.role === 'room_admin' ? 'Admin' : 'Mitglied' }}</span>
            <span style="display:flex;gap:6px" v-if="p.profile_id !== state.profile.id">
              <button class="btn btn-sm" @click="kickMember(p)">Kicken</button>
              <button class="btn btn-sm btn-danger" @click="banMember(p)">Sperren</button>
            </span>
          </div>
          <div v-for="p in state.room.bannedMembers" :key="'b' + p.profile_id" class="lb-row" style="grid-template-columns:30px minmax(0,1fr) auto auto">
            <span class="avatar" :style="{ background: 'var(--surface-3)', color: 'var(--faint)' }">{{ initials(p.profiles?.nickname) }}</span>
            <span class="player-name" style="color:var(--muted)">{{ p.profiles?.nickname }}</span>
            <span class="tag" style="color:var(--red);border-color:color-mix(in srgb,var(--red) 40%,var(--line-soft))">gesperrt</span>
            <button class="btn btn-sm" @click="unbanMember(p)">Entsperren</button>
          </div>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Wörter im Bulk hinzufügen</span></div>
        <p style="margin:0 0 10px;font-size:.82rem;color:var(--subtext)">
          Direkt als aktiv im Pool, ohne Vorschlag/Freigabe-Umweg – praktisch zum Import einer bestehenden Liste.
        </p>
        <textarea v-model="state.room.bulkWords" rows="6" placeholder="Ein Wort pro Zeile"></textarea>
        <button class="btn btn-primary btn-sm" style="margin-top:8px" @click="bulkAddWords">Hinzufügen</button>
      </div>
    </div>

    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Runden-Steuerung</span></div>
        <div class="field" style="margin-bottom:16px">
          <span class="field-label">Modus für die nächste Runde</span>
          <div class="seg" style="width:100%">
            <button style="flex:1" :aria-pressed="newRoundMode === 'first_blood'" @click="newRoundMode = 'first_blood'">First Blood</button>
            <button style="flex:1" :aria-pressed="newRoundMode === 'one_week_wipe'" @click="newRoundMode = 'one_week_wipe'">One-Week-Wipe</button>
          </div>
        </div>
        <button class="btn btn-primary btn-sm" @click="startNewRoundFromPool(newRoundMode)" :disabled="!!state.room.round && !state.room.round.ended_at">
          Neue Runde starten
        </button>
        <p class="note" style="margin-top:12px">
          Zieht die Wörter aus dem Wort-Pool (Top-Votes-Anteil im Tab „Wort-Pool" einstellbar). Mindestens 9 aktive Wörter nötig.
        </p>

        <div class="switch" style="margin-top:14px">
          <span class="switch-text">Freifeld in der Mitte<small>Klassisches Bingo-Freilos, nur bei 3×3/5×5-Boards</small></span>
          <button class="toggle" :aria-pressed="state.room.data?.free_space" @click="toggleFreeSpace" aria-label="Freifeld umschalten"></button>
        </div>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Raum-Einstellungen</span></div>
        <div class="field" style="margin-bottom:12px">
          <label class="field-label">Name</label>
          <input type="text" v-model="roomName" maxlength="60">
        </div>
        <div class="field" style="margin-bottom:12px">
          <span class="field-label">Sichtbarkeit</span>
          <div class="seg" style="width:100%">
            <button style="flex:1" :aria-pressed="roomVisibility === 'open'" @click="roomVisibility = 'open'">Offen</button>
            <button style="flex:1" :aria-pressed="roomVisibility === 'protected'" @click="roomVisibility = 'protected'">Geschützt</button>
            <button style="flex:1" :aria-pressed="roomVisibility === 'unlisted'" @click="roomVisibility = 'unlisted'">Versteckt</button>
          </div>
        </div>
        <div class="field" style="margin-bottom:12px" v-if="roomVisibility === 'protected'">
          <label class="field-label">Beitrittscode</label>
          <input type="text" v-model="roomCode" maxlength="20">
        </div>
        <button class="btn btn-primary btn-sm" @click="saveRoomSettings">Speichern</button>
      </div>
    </div>
  </div>
</template>
