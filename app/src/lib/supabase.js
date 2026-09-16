import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  console.error(
    'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY fehlen. Lokal: app/.env.local anlegen ' +
    '(siehe app/.env.example). Auf GitHub Pages: kommt aus den Repository Secrets über den Deploy-Workflow.'
  )
}

export const supabase = createClient(url || '', anonKey || '')

// Fest verdrahteter erster Raum, siehe konzept.md ("kleinerer erster Schritt").
export const MAIN_ROOM_ID = '00000000-0000-0000-0000-000000000001'
