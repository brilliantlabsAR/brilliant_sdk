import { defineConfig } from 'vite';
import dts from 'vite-plugin-dts';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.ts',
      name: 'brilliant-msg',
      fileName: (format) => `brilliant-msg.${format}.js`,
      formats: ['umd', 'es'],
    },
    outDir: 'dist',
    rollupOptions: {
      // Resolve these at install time from the consumer's node_modules, the way
      // the Python and Dart SDKs resolve their dependencies. Bundling them here
      // would snapshot a copy: dependency fixes could not reach users without
      // republishing this package, and a consumer importing both this package
      // and its dependency directly would end up with two separate copies of
      // the same classes.
      external: ['brilliant-ble'],
      output: {
        globals: {
          'brilliant-ble': 'brilliantBle',
        },
      },
    },
  },
  // pathsToAliases: false keeps 'brilliant-ble' as a package import in the
  // declarations. tsconfig's paths alias (there for TypeDoc) would otherwise be
  // rewritten into a relative path to the sibling's sources, which does not
  // exist in an installed package.
  plugins: [dts({ entryRoot: 'src', pathsToAliases: false })],
});
