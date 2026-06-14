import { defineConfig } from 'vite';

export default defineConfig({
  root: '.',
  build: {
    outDir: '../public',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8064',
        changeOrigin: true,
      }
    }
  }
});
