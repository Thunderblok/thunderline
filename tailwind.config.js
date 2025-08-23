/** Tailwind + daisyUI configuration for Thunderline
 *  Enables daisyUI themes and scans Phoenix templates & JS for class usage.
 */
module.exports = {
    content: [
        './assets/css/**/*.{css,pcss}',
        './assets/js/**/*.{js,ts,jsx,tsx}',
        './lib/**/*.{heex,ex,exs,leex}',
        './priv/**/*.html'
    ],
    darkMode: 'class',
    theme: {
        extend: {
            fontFamily: {
                sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif']
            }
        }
    },
    plugins: [
        require('./assets/vendor/daisyui.js')
    ],
    daisyui: {
        themes: [
            {
                thunderline: {
                    // Brand palette
                    'primary': '#10b981',
                    'primary-focus': '#059669',
                    'primary-content': '#04130d',
                    'secondary': '#6366f1',
                    'secondary-focus': '#4f46e5',
                    'secondary-content': '#0d1024',
                    'accent': '#ec4899',
                    'accent-focus': '#db2777',
                    'accent-content': '#16060f',
                    // Surfaces
                    'neutral': '#1f2937',
                    'neutral-focus': '#111827',
                    'neutral-content': '#e5e7eb',
                    'base-100': '#0f1115',
                    'base-200': '#161a21',
                    'base-300': '#1f2430',
                    'base-content': '#d1d5db',
                    // States
                    'info': '#0ea5e9',
                    'success': '#10b981',
                    'warning': '#f59e0b',
                    'error': '#f87171',
                    // Optional CSS var style tokens (daisyUI v5 still supports these custom keys)
                    '--rounded-box': '0.75rem',
                    '--rounded-btn': '0.5rem',
                    '--border-btn': '1px',
                    '--animation-btn': '0.25s',
                    '--btn-text-case': 'none'
                }
            },
            'dark', 'business', 'cyberpunk'
        ]
    }
};
