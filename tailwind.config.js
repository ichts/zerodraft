/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{html,js,ts}",
    "./prototype.html"
  ],
  theme: {
    extend: {
      colors: {
        // 主色调：纸张与墨水
        paper: '#FAFAF8',
        ink: '#1A1A1A',
        danger: '#C1403D',
        success: '#2E5930',
        ui: {
          DEFAULT: '#8B8B8B',
          light: '#D4D4D4',
        }
      },
      fontFamily: {
        // 主文本区域（中文 + 英文等宽）
        main: ['"LXGW WenKai"', '"霞鹜文楷"', '"IBM Plex Mono"', '"SF Mono"', 'monospace', 'serif'],
        // UI 文字（系统字体）
        ui: ['"PingFang SC"', '"SF Pro"', '-apple-system', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        'writing': '18px',
        'title': '32px',
        'ui': '14px',
        'timer': '12px',
      },
      maxWidth: {
        'writing': '720px',
      },
      spacing: {
        'xs': '8px',
        'sm': '16px',
        'md': '32px',
        'lg': '64px',
        'xl': '96px',
      },
      lineHeight: {
        'main': '1.8',
        'ui': '1.5',
      },
      transitionDuration: {
        'fast': '200ms',
        'medium': '400ms',
        'slow': '800ms',
        'blur': '3000ms',
      },
      transitionTimingFunction: {
        'smooth': 'ease-in-out',
      },
      keyframes: {
        'gentle-blur': {
          'from': { filter: 'blur(0)' },
          'to': { filter: 'blur(3px)' },
        },
        'gentle-pulse': {
          '0%, 100%': {
            boxShadow: '0 0 0 1px rgba(193, 64, 61, 0.2), 0 0 20px rgba(193, 64, 61, 0.1)',
          },
          '50%': {
            boxShadow: '0 0 0 2px rgba(193, 64, 61, 0.3), 0 0 30px rgba(193, 64, 61, 0.15)',
          },
        },
        'fade-in': {
          'from': { opacity: '0' },
          'to': { opacity: '1' },
        },
        'fade-out': {
          'from': { opacity: '1' },
          'to': { opacity: '0' },
        },
      },
      animation: {
        'gentle-blur': 'gentle-blur 3s ease-in-out forwards',
        'gentle-pulse': 'gentle-pulse 2s ease-in-out infinite',
        'fade-in': 'fade-in 800ms ease-out forwards',
        'fade-out': 'fade-out 400ms ease forwards',
      },
    },
  },
  plugins: [],
}
