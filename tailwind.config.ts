import type { Config } from 'tailwindcss'

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        display: ['Space Grotesk', 'sans-serif'],
        sans: ['DM Sans', 'sans-serif'],
        mono: ['JetBrains Mono', 'Menlo', 'monospace'],
      },
      colors: {
        arc: {
          50:  '#f0f6ff',
          100: '#dbeafe',
          200: '#acc6e9',
          300: '#85b1ed',
          400: '#5b8fd6',
          500: '#1061a6',
          600: '#122d45',
          700: '#0d1b2f',
          800: '#091524',
          900: '#060f1a',
        },
      },
    },
  },
  plugins: [],
} satisfies Config
