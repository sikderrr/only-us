import { defineConfig } from 'vitest/config'; import react from '@vitejs/plugin-react'; import tailwindcss from '@tailwindcss/vite';
export default defineConfig({plugins:[react(),tailwindcss()],base:process.env.GITHUB_ACTIONS?`/${process.env.GITHUB_REPOSITORY?.split('/')[1]??''}/`:'/',test:{environment:'node'}});
