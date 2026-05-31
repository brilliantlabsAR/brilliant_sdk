// example/vite.config.ts
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  base: '/brilliant_sdk/brilliant-ble/',
  root: __dirname,
  server: {
    open: true,
  },
  build: {
    // This will output the static site to 'example/dist'
    outDir: 'dist',
  },
  resolve: {
    alias: {
      // Option A: Use built library
      //'frame-ble': path.resolve(__dirname, '../dist/frame-ble.es.js'),

      // Option B Use source code instead of built bundle
      'brilliant-ble': path.resolve(__dirname, '../src/index.ts'),
    },
  },
});
