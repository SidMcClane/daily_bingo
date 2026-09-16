<script setup>
import { ref, computed, onMounted } from 'vue'
import {
  state,
  isMemberOf,
  isPendingIn,
  roleIn,
  joinOpenRoom,
  joinRoomWithCode,
  requestJoinRoom,
  cancelJoinRequest,
  leaveRoom,
  enterRoom,
  loadLobby,
} from '../store'
import { visLabel } from '../lib/helpers'

const codeDraft = ref({})

const myRooms = computed(() => state.myMemberships.filter((m) => m.status === 'active').map((m) => m.rooms))
const pendingRequests = computed(() => state.myMemberships.filter((m) => m.status === 'pending').map((m) => m.rooms))
const joinableRooms = computed(() =>
  state.rooms.filter((r) => !isMemberOf(r.id) && !isPendingIn(r.id))
)

onMounted(loadLobby)

function join(room) {
  if (room.visibility === 'protected' && codeDraft.value[room.id]) {
    joinRoomWithCode(room, codeDraft.value[room.id])
    codeDraft.value[room.id] = ''
  } else if (room.visibility === 'open') {
    joinOpenRoom(room)
  } else {
    requestJoinRoom(room)
  }
}
</script>

<template>
  <div>
    <div style="display:flex;align-items:baseline;gap:12px;flex-wrap:wrap;margin:22px 0 6px">
      <h1 style="font-size:1.4rem">Lobby</h1>
      <span class="mono" style="font-size:.72rem;color:var(--faint)">Teams und Events sind beides einfach Räume</span>
    </div>

    <h3 class="panel-title" style="margin:22px 0 10px">Meine Räume</h3>
    <div class="roomgrid" v-if="myRooms.length">
      <div v-for="r in myRooms" :key="r.id" class="roomcard" :class="{ current: r.id === state.room.id }">
        <div style="display:flex;justify-content:space-between;gap:8px;align-items:start">
          <h3>{{ r.name }}</h3>
          <span class="tag" :class="roleIn(r.id) === 'room_admin' ? 'active' : ''">
            {{ roleIn(r.id) === 'room_admin' ? 'Raum-Admin' : 'Mitglied' }}
          </span>
        </div>
        <p>{{ r.description || '—' }}</p>
        <div class="meta">
          <span class="chip mono">{{ visLabel(r.visibility) }}</span>
        </div>
        <div style="display:flex;gap:8px">
          <button class="btn btn-primary btn-sm btn-block" @click="enterRoom(r.id)">Spielen</button>
          <button class="btn btn-sm btn-danger" @click="leaveRoom(r.id)">Austreten</button>
        </div>
      </div>
    </div>
    <p v-else class="muted" style="font-size:.84rem;color:var(--faint)">Noch in keinem Raum Mitglied.</p>

    <h3 class="panel-title" style="margin:28px 0 10px">Offene Räume</h3>
    <div class="roomgrid" v-if="joinableRooms.length">
      <div v-for="r in joinableRooms" :key="r.id" class="roomcard">
        <div style="display:flex;justify-content:space-between;gap:8px;align-items:start">
          <h3>{{ r.name }}</h3>
          <span class="tag" :class="r.visibility === 'protected' ? 'proposed' : ''">{{ visLabel(r.visibility) }}</span>
        </div>
        <p>{{ r.description || '—' }}</p>
        <div v-if="r.visibility === 'protected'" class="field">
          <input type="text" v-model="codeDraft[r.id]" placeholder="Beitrittscode">
          <div style="display:flex;gap:8px">
            <button class="btn btn-primary btn-sm btn-block" @click="join(r)">Mit Code beitreten</button>
            <button class="btn btn-sm" @click="requestJoinRoom(r)">Anfragen</button>
          </div>
        </div>
        <button v-else class="btn btn-primary btn-sm btn-block" @click="join(r)">Beitreten</button>
      </div>
    </div>
    <p v-else class="muted" style="font-size:.84rem;color:var(--faint)">Keine weiteren Räume sichtbar.</p>

    <div v-if="pendingRequests.length">
      <h3 class="panel-title" style="margin:28px 0 10px">Offene Anfragen</h3>
      <div class="lb">
        <div v-for="r in pendingRequests" :key="'p' + r.id" class="lb-row" style="grid-template-columns:minmax(0,1fr) auto auto">
          <span class="player-name">{{ r.name }}</span>
          <span class="tag proposed">angefragt</span>
          <button class="btn btn-sm" @click="cancelJoinRequest(r.id)">Zurückziehen</button>
        </div>
      </div>
    </div>

    <p class="note" style="margin-top:22px">
      Nicht gelistete Räume erscheinen hier bewusst nicht – die findet nur, wer den Link oder den Code kennt.
    </p>
  </div>
</template>
