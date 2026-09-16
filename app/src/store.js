import { reactive } from 'vue'
import { supabase } from './lib/supabase'
import { gridSizeFor, lineIndexes, hashSeed, seededShuffle, dayKey, DAY } from './lib/helpers'

export const state = reactive({
  session: null,
  profile: null,
  bootstrapped: false,
  view: 'lobby', // 'lobby' | 'profile' | 'platform' | 'room'
  error: '',
  toast: '',

  rooms: [], // alle für mich sichtbaren Räume
  myMemberships: [], // room_members (mine), rooms eingebettet

  platform: {
    pendingUsers: [],
    blockedUsers: [],
    allRooms: [],
    newRoomName: '',
    newRoomVisibility: 'open',
    newRoomCode: '',
  },

  room: {
    id: null,
    data: null,
    tab: 'board',
    myRole: null,
    myStatus: null,
    members: [], // aktive Mitglieder inkl. profil
    joinRequests: [],
    bannedMembers: [],
    round: null,
    marksAll: [], // { word, profile_id } für die laufende Runde
    wordPool: [],
    wordVotesMine: new Set(),
    wordVoteCounts: {}, // word_id -> Anzahl Stimmen
    wordHitCounts: {}, // word -> Anzahl je gerufen (über alle Runden)
    wins: [], // alle wins-Zeilen des Raums (für Rangliste/Kalender)
    onlineIds: new Set(),
    wordFilter: 'all',
    lbRange: 'week',
    topCount: 15,
    bulkWords: '',
    newWord: '',
  },

  winner: null,
})

let realtimeChannel = null
let presenceChannel = null
let toastTimer = null

export function showToast(msg) {
  state.toast = msg
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { state.toast = '' }, 2600)
}

function fail(label, err) {
  state.error = label + ': ' + (err?.message || err)
}

// ---------------------------------------------------------------- AUTH ----

export async function login() {
  await supabase.auth.signInWithOAuth({ provider: 'github', options: { redirectTo: window.location.href } })
}

export async function logout() {
  await leaveRoomView()
  await supabase.auth.signOut()
  state.profile = null
  state.session = null
  state.view = 'lobby'
}

export function initAuth() {
  supabase.auth.onAuthStateChange((_event, s) => {
    const had = !!state.session
    state.session = s
    if (s && !had) bootstrap()
    else if (!s) {
      state.profile = null
      state.bootstrapped = false
    }
  })
}

async function bootstrap() {
  await loadProfile()
  if (state.profile?.status === 'approved') {
    await loadLobby()
  }
  state.bootstrapped = true
}

async function loadProfile() {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', state.session.user.id).maybeSingle()
  if (error) return fail('Profil laden', error)
  state.profile = data
}

export async function updateNickname(nickname) {
  const { error } = await supabase.from('profiles').update({ nickname }).eq('id', state.profile.id)
  if (error) return fail('Nickname speichern', error)
  state.profile.nickname = nickname
  showToast('Nickname gespeichert')
}

export async function updateColor(color) {
  const { error } = await supabase.from('profiles').update({ color }).eq('id', state.profile.id)
  if (error) return fail('Farbe speichern', error)
  state.profile.color = color
}

// --------------------------------------------------------------- LOBBY ----

export async function loadLobby() {
  const [{ data: rooms, error: roomsErr }, { data: memberships, error: memErr }] = await Promise.all([
    supabase.from('rooms').select('*').order('created_at', { ascending: true }),
    supabase
      .from('room_members')
      .select('role, status, joined_at, room_id, rooms(*)')
      .eq('profile_id', state.profile.id),
  ])
  if (roomsErr) return fail('Räume laden', roomsErr)
  if (memErr) return fail('Mitgliedschaften laden', memErr)
  state.rooms = rooms || []
  state.myMemberships = memberships || []
}

export const isMemberOf = (roomId) =>
  state.myMemberships.some((m) => m.room_id === roomId && m.status === 'active')
export const isPendingIn = (roomId) =>
  state.myMemberships.some((m) => m.room_id === roomId && m.status === 'pending')
export const roleIn = (roomId) => state.myMemberships.find((m) => m.room_id === roomId)?.role || null

export async function joinOpenRoom(room) {
  const { error } = await supabase
    .from('room_members')
    .insert({ room_id: room.id, profile_id: state.profile.id, role: 'member', status: 'active' })
  if (error) return fail('Beitreten', error)
  showToast('„' + room.name + '" beigetreten')
  await loadLobby()
}

export async function joinRoomWithCode(room, code) {
  const { error } = await supabase.rpc('join_room_with_code', { target_room: room.id, code })
  if (error) return fail('Beitreten mit Code', error)
  showToast('„' + room.name + '" beigetreten')
  await loadLobby()
}

export async function requestJoinRoom(room) {
  const { error } = await supabase
    .from('room_members')
    .insert({ room_id: room.id, profile_id: state.profile.id, role: 'member', status: 'pending' })
  if (error) return fail('Anfrage stellen', error)
  showToast('Anfrage gestellt – wartet auf Freigabe durch den Raum-Admin')
  await loadLobby()
}

export async function cancelJoinRequest(roomId) {
  const { error } = await supabase
    .from('room_members')
    .delete()
    .eq('room_id', roomId)
    .eq('profile_id', state.profile.id)
    .eq('status', 'pending')
  if (error) return fail('Anfrage zurückziehen', error)
  await loadLobby()
}

export async function leaveRoom(roomId) {
  if (!confirm('Raum wirklich verlassen?')) return
  const { error } = await supabase.from('room_members').delete().eq('room_id', roomId).eq('profile_id', state.profile.id)
  if (error) return fail('Raum verlassen', error)
  showToast('Raum verlassen')
  if (state.room.id === roomId) await leaveRoomView()
  await loadLobby()
}

// -------------------------------------------------------- PLATTFORM-ADMIN ----

export async function loadPlatformData() {
  const [{ data: pending, error: e1 }, { data: blocked, error: e2 }, { data: rooms, error: e3 }] = await Promise.all([
    supabase.from('profiles').select('*').eq('status', 'pending'),
    supabase.from('profiles').select('*').eq('status', 'blocked'),
    supabase.from('rooms').select('*, room_members(count)').order('created_at', { ascending: true }),
  ])
  if (e1) return fail('Freigaben laden', e1)
  if (e2) return fail('Gesperrte laden', e2)
  if (e3) return fail('Räume laden', e3)
  state.platform.pendingUsers = pending || []
  state.platform.blockedUsers = blocked || []
  state.platform.allRooms = rooms || []
}

export async function approveUser(profile) {
  const { error } = await supabase.from('profiles').update({ status: 'approved' }).eq('id', profile.id)
  if (error) return fail('Freigeben', error)
  showToast(profile.nickname + ' ist freigegeben')
  await loadPlatformData()
}

export async function blockUser(profile) {
  const { error } = await supabase.from('profiles').update({ status: 'blocked' }).eq('id', profile.id)
  if (error) return fail('Sperren', error)
  showToast(profile.nickname + ' ist gesperrt')
  await loadPlatformData()
}

export async function createRoom() {
  const name = state.platform.newRoomName.trim()
  if (!name) return
  const payload = {
    name,
    visibility: state.platform.newRoomVisibility,
    join_code: state.platform.newRoomCode.trim() || null,
    created_by: state.profile.id,
  }
  const { error } = await supabase.from('rooms').insert(payload)
  if (error) return fail('Raum anlegen', error)
  state.platform.newRoomName = ''
  state.platform.newRoomCode = ''
  showToast('Raum angelegt')
  await loadPlatformData()
  await loadLobby()
}

export async function deleteRoomAsAdmin(room) {
  if (!confirm('Raum „' + room.name + '" wirklich löschen?')) return
  const { error } = await supabase.from('rooms').delete().eq('id', room.id)
  if (error) return fail('Raum löschen', error)
  showToast('Raum gelöscht')
  if (state.room.id === room.id) await leaveRoomView()
  await loadPlatformData()
  await loadLobby()
}

// ----------------------------------------------------------------- ROOM ----

export async function enterRoom(roomId) {
  await leaveRoomView()
  state.room.id = roomId
  state.view = 'room'
  state.room.tab = 'board'
  await loadRoomAll()
  subscribeRoomRealtime(roomId)
}

export async function leaveRoomView() {
  if (realtimeChannel) {
    supabase.removeChannel(realtimeChannel)
    realtimeChannel = null
  }
  if (presenceChannel) {
    supabase.removeChannel(presenceChannel)
    presenceChannel = null
  }
  state.room.id = null
  state.room.data = null
  state.room.round = null
}

async function loadRoomAll() {
  await Promise.all([loadRoomData(), loadRoomMembers(), loadRound(), loadWordPool(), loadWins()])
}

async function loadRoomData() {
  const { data, error } = await supabase.from('rooms').select('*').eq('id', state.room.id).maybeSingle()
  if (error) return fail('Raum laden', error)
  state.room.data = data
}

async function loadRoomMembers() {
  const { data, error } = await supabase
    .from('room_members')
    .select('role, status, joined_at, profile_id, profiles(id, nickname, color)')
    .eq('room_id', state.room.id)
  if (error) return fail('Mitglieder laden', error)
  const mine = (data || []).find((m) => m.profile_id === state.profile.id)
  state.room.myRole = mine?.role || null
  state.room.myStatus = mine?.status || null
  state.room.members = (data || []).filter((m) => m.status === 'active')
  state.room.joinRequests = (data || []).filter((m) => m.status === 'pending')
  state.room.bannedMembers = (data || []).filter((m) => m.status === 'banned')
}

export const isRoomAdmin = () => state.room.myRole === 'room_admin'

async function loadRound() {
  const { data, error } = await supabase
    .from('rounds')
    .select('*')
    .eq('room_id', state.room.id)
    .is('ended_at', null)
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) return fail('Runde laden', error)
  state.room.round = data
  if (data) await loadMarks(data.id)
  else state.room.marksAll = []
}

async function loadMarks(roundId) {
  const { data, error } = await supabase.from('marks').select('word, profile_id').eq('round_id', roundId)
  if (error) return fail('Markierungen laden', error)
  state.room.marksAll = data || []
}

async function loadWordPool() {
  const { data: pool, error: e1 } = await supabase.from('word_pool').select('*').eq('room_id', state.room.id)
  if (e1) return fail('Wort-Pool laden', e1)
  state.room.wordPool = pool || []
  const poolIds = (pool || []).map((w) => w.id)

  const [{ data: allVotes, error: e2 }, { data: marksHistory, error: e3 }] = await Promise.all([
    poolIds.length
      ? supabase.from('word_votes').select('word_id, profile_id').in('word_id', poolIds)
      : Promise.resolve({ data: [], error: null }),
    supabase.from('marks').select('word, rounds!inner(room_id)').eq('rounds.room_id', state.room.id),
  ])
  if (e2) return fail('Stimmen laden', e2)
  if (e3) return fail('Trefferquote laden', e3)

  const voteCounts = {}
  const mine = new Set()
  ;(allVotes || []).forEach((v) => {
    voteCounts[v.word_id] = (voteCounts[v.word_id] || 0) + 1
    if (v.profile_id === state.profile.id) mine.add(v.word_id)
  })
  state.room.wordVoteCounts = voteCounts
  state.room.wordVotesMine = mine

  const hitCounts = {}
  ;(marksHistory || []).forEach((m) => { hitCounts[m.word] = (hitCounts[m.word] || 0) + 1 })
  state.room.wordHitCounts = hitCounts
}

export const votesFor = (wordId) => state.room.wordVoteCounts?.[wordId] || 0

async function loadWins() {
  const { data, error } = await supabase
    .from('wins')
    .select('id, profile_id, lines_count, achieved_at, round_id, profiles(nickname, color)')
    .eq('room_id', state.room.id)
    .order('achieved_at', { ascending: false })
  if (error) return fail('Bestenliste laden', error)
  state.room.wins = data || []
}

function subscribeRoomRealtime(roomId) {
  realtimeChannel = supabase
    .channel('room-data-' + roomId)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'rounds', filter: `room_id=eq.${roomId}` }, () => loadRound())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'wins', filter: `room_id=eq.${roomId}` }, () => loadWins())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'marks' }, (p) => {
      const rec = p.new || p.old
      if (state.room.round && rec.round_id === state.room.round.id) loadMarks(state.room.round.id)
      // Trefferquote im Wort-Pool hängt an marks über alle Runden - mitziehen.
      loadWordPool()
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'room_members', filter: `room_id=eq.${roomId}` }, () => loadRoomMembers())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'word_pool', filter: `room_id=eq.${roomId}` }, () => loadWordPool())
    .on('postgres_changes', { event: '*', schema: 'public', table: 'word_votes' }, () => loadWordPool())
    .subscribe()

  presenceChannel = supabase.channel('room-presence-' + roomId, { config: { presence: { key: state.profile.id } } })
  presenceChannel
    .on('presence', { event: 'sync' }, () => {
      const s = presenceChannel.presenceState()
      state.room.onlineIds = new Set(Object.keys(s))
    })
    .subscribe(async (status) => {
      if (status === 'SUBSCRIBED') await presenceChannel.track({ online_at: Date.now() })
    })
}

// ------------------------------------------------------------ BOARD/BINGO ----

export const gridSize = () => gridSizeFor(state.room.round?.words?.length || 0)

export function boardWordsFor() {
  const round = state.room.round
  if (!round) return []
  const size = gridSize()
  if (!size) return []
  const cellCount = size * size
  const trimmed = round.words.slice(0, cellCount)
  const seed = hashSeed(round.id + state.profile.id)
  return seededShuffle(trimmed, seed)
}

export function linesForSize() {
  const size = gridSize()
  return size ? lineIndexes(size) : []
}

export async function toggleCell(word) {
  const round = state.room.round
  if (!round) return
  const already = state.room.marksAll.some((m) => m.word === word && m.profile_id === state.profile.id)
  if (already) {
    state.room.marksAll = state.room.marksAll.filter((m) => !(m.word === word && m.profile_id === state.profile.id))
    await supabase.from('marks').delete().eq('round_id', round.id).eq('word', word).eq('profile_id', state.profile.id)
    return
  }
  state.room.marksAll.push({ word, profile_id: state.profile.id })
  const { error } = await supabase.from('marks').insert({ round_id: round.id, profile_id: state.profile.id, word })
  if (error) return fail('Markieren', error)
  await checkForNewBingo()
}

const reportedLines = new Set()

async function checkForNewBingo() {
  const words = boardWordsFor()
  const mine = new Set(state.room.marksAll.filter((m) => m.profile_id === state.profile.id).map((m) => m.word))
  const fresh = []
  linesForSize().forEach((line, idx) => {
    const key = state.room.round.id + '-' + idx
    if (line.every((i) => mine.has(words[i])) && !reportedLines.has(key)) {
      reportedLines.add(key)
      fresh.push(line)
    }
  })
  if (!fresh.length) return
  const { data, error } = await supabase.rpc('report_win', {
    target_round: state.room.round.id,
    p_lines_count: fresh.length,
  })
  if (error) return fail('Bingo melden', error)
  state.winner = {
    words: fresh[0].map((i) => words[i]),
    count: fresh.length,
    win: data,
  }
  await loadRound()
  await loadWins()
}

export function closeWinnerModal() {
  state.winner = null
}

// ------------------------------------------------------------ RAUM-ADMIN ----

export async function bulkAddWords() {
  const words = state.room.bulkWords
    .split('\n')
    .map((w) => w.trim())
    .filter(Boolean)
  if (!words.length) return
  const rows = words.map((word) => ({
    room_id: state.room.id,
    word,
    suggested_by: state.profile.id,
    status: 'active',
  }))
  const { error } = await supabase.from('word_pool').upsert(rows, { onConflict: 'room_id,word', ignoreDuplicates: true })
  if (error) return fail('Wörter hinzufügen', error)
  state.room.bulkWords = ''
  showToast(words.length + ' Wörter hinzugefügt')
  await loadWordPool()
}

export async function proposeWord() {
  const text = state.room.newWord.trim()
  if (!text) return
  const { error } = await supabase
    .from('word_pool')
    .insert({ room_id: state.room.id, word: text, suggested_by: state.profile.id, status: 'proposed' })
  if (error) return fail('Vorschlagen', error)
  state.room.newWord = ''
  showToast('Vorschlag eingereicht – wartet auf Freigabe')
  await loadWordPool()
}

export async function toggleVote(word) {
  const voted = state.room.wordVotesMine.has(word.id)
  if (voted) {
    await supabase.from('word_votes').delete().eq('word_id', word.id).eq('profile_id', state.profile.id)
  } else {
    const { error } = await supabase.from('word_votes').insert({ word_id: word.id, profile_id: state.profile.id })
    if (error) return fail('Voten', error)
  }
  await loadWordPool()
}

export async function approveWord(word) {
  const { error } = await supabase.from('word_pool').update({ status: 'active' }).eq('id', word.id)
  if (error) return fail('Freigeben', error)
  await loadWordPool()
}

export async function rejectWord(word) {
  const { error } = await supabase.from('word_pool').update({ status: 'rejected' }).eq('id', word.id)
  if (error) return fail('Ablehnen', error)
  await loadWordPool()
}

export async function approveMember(member) {
  const { error } = await supabase
    .from('room_members')
    .update({ status: 'active' })
    .eq('room_id', state.room.id)
    .eq('profile_id', member.profile_id)
  if (error) return fail('Aufnehmen', error)
  showToast(member.profiles.nickname + ' ist jetzt Mitglied')
  await loadRoomMembers()
}

export async function denyMember(member) {
  const { error } = await supabase
    .from('room_members')
    .delete()
    .eq('room_id', state.room.id)
    .eq('profile_id', member.profile_id)
  if (error) return fail('Ablehnen', error)
  await loadRoomMembers()
}

export async function kickMember(member) {
  const { error } = await supabase
    .from('room_members')
    .delete()
    .eq('room_id', state.room.id)
    .eq('profile_id', member.profile_id)
  if (error) return fail('Kicken', error)
  await loadRoomMembers()
}

export async function banMember(member) {
  const { error } = await supabase
    .from('room_members')
    .update({ status: 'banned' })
    .eq('room_id', state.room.id)
    .eq('profile_id', member.profile_id)
  if (error) return fail('Sperren', error)
  await loadRoomMembers()
}

export async function unbanMember(member) {
  const { error } = await supabase
    .from('room_members')
    .update({ status: 'active' })
    .eq('room_id', state.room.id)
    .eq('profile_id', member.profile_id)
  if (error) return fail('Entsperren', error)
  await loadRoomMembers()
}

export async function updateRoomSettings(name, visibility, joinCode) {
  const { error } = await supabase
    .from('rooms')
    .update({ name, visibility, join_code: joinCode || null })
    .eq('id', state.room.id)
  if (error) return fail('Raum-Einstellungen speichern', error)
  showToast('Gespeichert')
  await loadRoomData()
}

export async function startNewRoundFromPool(mode) {
  const active = state.room.wordPool.filter((w) => w.status === 'active')
  if (active.length < 9) {
    state.error = 'Mindestens 9 aktive Wörter im Pool nötig, um eine Runde zu starten.'
    return
  }
  const byVotes = [...active].sort((a, b) => votesFor(b.id) - votesFor(a.id))
  const topN = Math.min(state.room.topCount, active.length)
  const top = byVotes.slice(0, topN)
  const rest = byVotes.slice(topN)
  const filler = seededShuffle(rest, Date.now() & 0xffffffff)
  const words = [...top, ...filler].map((w) => w.word)

  const { error } = await supabase.from('rounds').insert({ room_id: state.room.id, mode, words })
  if (error) return fail('Runde starten', error)
  await loadRound()
}

export { DAY, dayKey }
