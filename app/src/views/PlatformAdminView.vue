<script setup>
import { onMounted } from 'vue'
import { state, loadPlatformData, approveUser, blockUser, createRoom, deleteRoomAsAdmin } from '../store'
import { hueFor, initials, visLabel } from '../lib/helpers'

onMounted(loadPlatformData)

function memberCount(room) {
  return room.room_members?.[0]?.count ?? 0
}
</script>

<template>
  <div class="layout">
    <div class="stack">
      <div class="panel">
        <div class="panel-head">
          <span class="panel-title">Freigaben</span>
          <span class="chip" v-if="state.platform.pendingUsers.length">{{ state.platform.pendingUsers.length }} offen</span>
        </div>
        <p style="margin:0 0 12px;font-size:.82rem;color:var(--subtext)">
          Wer sich neu per GitHub anmeldet, landet hier – bis zur Freigabe sieht diese Person nichts von der Anwendung.
        </p>
        <div class="lb" v-if="state.platform.pendingUsers.length">
          <div v-for="u in state.platform.pendingUsers" :key="u.id" class="lb-row" style="grid-template-columns:30px minmax(0,1fr) auto">
            <span class="avatar" :style="{ background: hueFor(u) }">{{ initials(u.nickname) }}</span>
            <span class="player-name">{{ u.nickname }}</span>
            <span style="display:flex;gap:6px">
              <button class="btn btn-sm btn-primary" @click="approveUser(u)">Freigeben</button>
              <button class="btn btn-sm btn-danger" @click="blockUser(u)">Sperren</button>
            </span>
          </div>
        </div>
        <p v-else style="margin:0;font-size:.84rem;color:var(--faint)">Keine offenen Anfragen.</p>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Gesperrte Accounts</span></div>
        <div class="lb" v-if="state.platform.blockedUsers.length">
          <div v-for="u in state.platform.blockedUsers" :key="u.id" class="lb-row" style="grid-template-columns:30px minmax(0,1fr) auto">
            <span class="avatar" :style="{ background: 'var(--surface-3)', color: 'var(--faint)' }">{{ initials(u.nickname) }}</span>
            <span class="player-name" style="color:var(--muted)">{{ u.nickname }}</span>
            <button class="btn btn-sm" @click="approveUser(u)">Entsperren</button>
          </div>
        </div>
        <p v-else style="margin:0;font-size:.84rem;color:var(--faint)">Niemand gesperrt.</p>
        <p class="note" style="margin-top:14px">
          Eine Sperre bleibt als Markierung stehen, statt den Datensatz zu löschen.
        </p>
      </div>
    </div>

    <div class="stack">
      <div class="panel">
        <div class="panel-head"><span class="panel-title">Neuen Raum anlegen</span></div>
        <div class="field" style="margin-bottom:10px">
          <label class="field-label">Name</label>
          <input type="text" v-model="state.platform.newRoomName" maxlength="60" placeholder="z. B. Team Frontend">
        </div>
        <div class="field" style="margin-bottom:10px">
          <span class="field-label">Sichtbarkeit</span>
          <div class="seg" style="width:100%">
            <button style="flex:1" :aria-pressed="state.platform.newRoomVisibility === 'open'" @click="state.platform.newRoomVisibility = 'open'">Offen</button>
            <button style="flex:1" :aria-pressed="state.platform.newRoomVisibility === 'protected'" @click="state.platform.newRoomVisibility = 'protected'">Geschützt</button>
            <button style="flex:1" :aria-pressed="state.platform.newRoomVisibility === 'unlisted'" @click="state.platform.newRoomVisibility = 'unlisted'">Versteckt</button>
          </div>
        </div>
        <div class="field" style="margin-bottom:12px" v-if="state.platform.newRoomVisibility === 'protected'">
          <label class="field-label">Beitrittscode</label>
          <input type="text" v-model="state.platform.newRoomCode" maxlength="20" placeholder="z. B. FE2026">
        </div>
        <button class="btn btn-primary btn-block" @click="createRoom">Raum anlegen</button>
      </div>

      <div class="panel">
        <div class="panel-head"><span class="panel-title">Alle Räume</span></div>
        <div class="lb">
          <div v-for="r in state.platform.allRooms" :key="r.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto auto">
            <span class="player-name">{{ r.name }}<small class="mono" style="display:block;color:var(--faint);font-size:.66rem">{{ memberCount(r) }} Mitglieder</small></span>
            <span class="tag" :class="r.visibility === 'open' ? 'active' : 'proposed'">{{ visLabel(r.visibility) }}</span>
            <button class="btn btn-sm btn-danger" @click="deleteRoomAsAdmin(r)">Löschen</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
