<script setup>
import { onMounted, computed } from 'vue'
import { state, initAuth, login, logout, showToast, leaveRoomView } from './store'
import { hueFor, initials } from './lib/helpers'
import LobbyView from './views/LobbyView.vue'
import ProfileView from './views/ProfileView.vue'
import PlatformAdminView from './views/PlatformAdminView.vue'
import RoomView from './views/RoomView.vue'

const isApproved = computed(() => state.profile?.status === 'approved')
const isPlatformAdmin = computed(() => state.profile?.is_platform_admin === true)

function goto(view) {
  if (view !== 'room') leaveRoomView()
  state.view = view
}

onMounted(initAuth)
</script>

<template>
  <!-- ===== LOGIN ===== -->
  <div class="shell" v-if="!state.session">
    <div class="center-screen">
      <div class="authcard">
        <div style="font-size:2rem;margin-bottom:8px">🎲</div>
        <h2>Dev Daily Bingo</h2>
        <p>Anmeldung über GitHub.</p>
        <button class="btn gh-btn" @click="login">Mit GitHub anmelden</button>
      </div>
    </div>
  </div>

  <!-- ===== LADEN ===== -->
  <div class="shell" v-else-if="!state.bootstrapped">
    <div class="center-screen"><p class="mono" style="color:var(--faint)">Lade…</p></div>
  </div>

  <!-- ===== PENDING GLOBAL APPROVAL ===== -->
  <div class="shell" v-else-if="!isApproved">
    <div class="center-screen">
      <div class="authcard">
        <div style="font-size:2rem;margin-bottom:8px">⏳</div>
        <h2>Warte auf Freigabe</h2>
        <p>
          Dein Account <b class="mono">{{ state.profile?.nickname }}</b> ist angemeldet, aber noch nicht freigeschaltet.
          Sobald der Betreiber dich freigibt, geht's los.
        </p>
        <button class="btn btn-block" @click="logout">Abmelden</button>
      </div>
    </div>
  </div>

  <!-- ===== APP ===== -->
  <template v-else>
    <header class="topbar">
      <div class="topbar-inner">
        <div class="brand">
          <span>🎲</span>
          <span class="brand-name">Daily Bingo</span>
          <span class="brand-sub" v-if="state.view === 'room' && state.room.data">{{ state.room.data.name }}</span>
        </div>

        <span class="chip role plat" v-if="isPlatformAdmin">Plattform-Admin</span>
        <span class="chip role" v-else-if="state.view === 'room' && state.room.myRole === 'room_admin'">Raum-Admin</span>

        <nav class="nav">
          <button class="navlink" :class="{ active: state.view === 'lobby' }" @click="goto('lobby')">Lobby</button>
          <button class="navlink" :class="{ active: state.view === 'room' }" @click="state.view = 'room'" v-if="state.room.id">
            Spielen
          </button>
          <button class="navlink" :class="{ active: state.view === 'profile' }" @click="goto('profile')">Profil</button>
          <button class="navlink" :class="{ active: state.view === 'platform' }" @click="goto('platform')" v-if="isPlatformAdmin">
            Plattform
          </button>
          <button class="me-chip" @click="goto('profile')">
            <span class="avatar" :style="{ background: hueFor(state.profile) }">{{ initials(state.profile?.nickname) }}</span>
            {{ state.profile?.nickname }}
          </button>
        </nav>
      </div>
    </header>

    <div class="shell">
      <p v-if="state.error" class="note" style="color:var(--red);border-color:var(--red);margin-bottom:16px">{{ state.error }}</p>

      <LobbyView v-if="state.view === 'lobby'" />
      <ProfileView v-else-if="state.view === 'profile'" />
      <PlatformAdminView v-else-if="state.view === 'platform'" />
      <RoomView v-else-if="state.view === 'room' && state.room.id" />
    </div>
  </template>

  <!-- ===== OVERLAYS ===== -->
  <div class="scrim" v-if="state.winner">
    <div class="modal">
      <h2>BINGO! 🎯</h2>
      <p style="margin:0;color:var(--subtext);font-size:.86rem">
        {{ state.winner.count > 1 ? state.winner.count + ' Linien auf einen Schlag.' : 'Eine Linie vollendet.' }}
      </p>
      <div class="win-line">
        <span class="win-word" v-for="(w, i) in state.winner.words" :key="i">{{ w }}</span>
      </div>
      <button class="btn btn-primary" @click="state.winner = null">Weiterspielen</button>
    </div>
  </div>

  <div class="toast" v-if="state.toast">{{ state.toast }}</div>
</template>
