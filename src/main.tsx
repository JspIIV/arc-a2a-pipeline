import React from 'react'
import ReactDOM from 'react-dom/client'
import { WagmiProvider } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ConnectKitProvider } from 'connectkit'
import { Toaster } from 'sonner'
import App from './App'
import { config } from './config'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 10_000 } },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <ConnectKitProvider
          customTheme={{
            '--ck-font-family': "'DM Sans', sans-serif",
            '--ck-primary-button-background': '#acc6e9',
            '--ck-primary-button-hover-background': '#cbdbf2',
            '--ck-primary-button-color': '#0d1b2f',
            '--ck-body-background': '#1f2f44',
            '--ck-body-background-secondary': '#0d1b2f',
            '--ck-body-color': '#f9faf3',
            '--ck-body-color-muted': '#94a3b8',
            '--ck-overlay-background': 'rgba(6,15,26,0.8)',
            '--ck-border-radius': '16px',
          }}
        >
          <Toaster
            position="top-right"
            toastOptions={{
              style: {
                background: '#1f2f44',
                border: '1px solid rgba(203,219,242,0.18)',
                color: '#f9faf3',
                fontFamily: "'DM Sans', sans-serif",
              },
            }}
          />
          <App />
        </ConnectKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>,
)
