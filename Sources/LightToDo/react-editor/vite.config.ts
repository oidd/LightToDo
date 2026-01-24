import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [react(), viteSingleFile()],
    base: './', // Local file support
    build: {
        outDir: 'dist',
        assetsDir: '', // Put assets in root of dist for simpler paths
        assetsInlineLimit: 100000000, // Inline all assets
        cssCodeSplit: false,
        rollupOptions: {
            output: {
                inlineDynamicImports: true,
            }
        }
    },
    define: {
        // Fix for inline defines in some libraries
        'process.env': {}
    }
})
