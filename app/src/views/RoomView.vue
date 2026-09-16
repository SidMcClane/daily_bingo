<script setup>
import { computed } from 'vue'
import { state, isRoomAdmin } from '../store'
import BoardTab from '../components/room/BoardTab.vue'
import RankTab from '../components/room/RankTab.vue'
import WordsTab from '../components/room/WordsTab.vue'
import AdminTab from '../components/room/AdminTab.vue'

const proposedCount = computed(() => state.room.wordPool.filter((w) => w.status === 'proposed').length)
const joinRequestCount = computed(() => state.room.joinRequests.length)
</script>

<template>
  <div>
    <nav class="tabs" role="tablist">
      <button class="tab" role="tab" :aria-selected="state.room.tab === 'board'" @click="state.room.tab = 'board'">Board</button>
      <button class="tab" role="tab" :aria-selected="state.room.tab === 'rank'" @click="state.room.tab = 'rank'">Rangliste</button>
      <button class="tab" role="tab" :aria-selected="state.room.tab === 'words'" @click="state.room.tab = 'words'">
        Wort-Pool <span class="tab-badge" v-if="proposedCount">{{ proposedCount }}</span>
      </button>
      <button class="tab" role="tab" :aria-selected="state.room.tab === 'admin'" @click="state.room.tab = 'admin'" v-if="isRoomAdmin()">
        Raum-Admin <span class="tab-badge alert" v-if="joinRequestCount">{{ joinRequestCount }}</span>
      </button>
    </nav>

    <BoardTab v-show="state.room.tab === 'board'" />
    <RankTab v-show="state.room.tab === 'rank'" />
    <WordsTab v-show="state.room.tab === 'words'" />
    <AdminTab v-show="state.room.tab === 'admin'" v-if="isRoomAdmin()" />
  </div>
</template>
