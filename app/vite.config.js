import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// GitHub Pages liefert das Repo unter /daily_bingo/ aus, sonst brechen
// die Asset-Pfade im Build (siehe konzept.md, Abschnitt "Migration zu Vue").
export default defineConfig({
  base: '/daily_bingo/',
  plugins: [vue()],
})
