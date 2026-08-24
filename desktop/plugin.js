import {
  cn,
  Codicon,
  host,
  PALETTE_AREA,
  ROUTES_AREA,
  SIDEBAR_NAV_AREA,
  STATUSBAR_AREAS,
  Tip,
  useQuery
} from '@hermes/plugin-sdk'
import { jsx, jsxs } from 'react/jsx-runtime'

const ID = 'provider-quota'
let rest

function useQuotas() {
  return useQuery({
    queryKey: [ID, 'quotas'],
    queryFn: () => rest('/quotas?refresh=true'),
    refetchInterval: 60_000,
    staleTime: 55_000
  })
}

function formatPercent(value) {
  return value == null ? '—' : `${Math.round(value)}%`
}

function formatAmount(value, currency) {
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: currency ?? 'USD'
  }).format(value)
}

function QuotaWindow({ window }) {
  const hasAmount = window.remaining_amount != null
  const value = hasAmount
    ? `${formatAmount(window.remaining_amount, window.currency)} available`
    : `${formatPercent(window.remaining_percent)} remaining`

  return jsxs('div', {
    className: 'flex flex-col gap-1 rounded-md border border-(--ui-stroke-secondary) p-3',
    children: [
      jsxs('div', {
        className: 'flex items-center justify-between gap-3',
        children: [
          jsx('span', { className: 'font-medium', children: window.label }),
          jsx('span', {
            className: cn('tabular-nums', window.warning ? 'text-(--ui-warning)' : 'text-(--ui-text-secondary)'),
            children: value
          })
        ]
      }),
      window.used_percent == null
        ? null
        : jsx('div', {
            className: 'h-1.5 overflow-hidden rounded-full bg-(--ui-surface-secondary)',
            children: jsx('div', {
              className: cn('h-full rounded-full', window.warning ? 'bg-(--ui-warning)' : 'bg-(--ui-accent)'),
              style: { width: `${window.used_percent}%` }
            })
          }),
      window.resets_at
        ? jsx('span', {
            className: 'text-xs text-(--ui-text-tertiary)',
            children: `Resets ${new Date(window.resets_at).toLocaleString()}`
          })
        : null,
      window.detail
        ? jsx('span', { className: 'text-xs text-(--ui-text-tertiary)', children: window.detail })
        : null
    ]
  })
}

function ProviderCard({ provider }) {
  return jsxs('section', {
    className: 'flex flex-col gap-3 rounded-lg border border-(--ui-stroke-secondary) p-4',
    children: [
      jsxs('div', {
        className: 'flex items-center justify-between gap-3',
        children: [
          jsxs('div', {
            className: 'flex items-center gap-2',
            children: [
              jsx(Codicon, { name: provider.status === 'ok' ? 'pulse' : 'warning', size: '0.9rem' }),
              jsx('h2', { className: 'font-semibold', children: provider.label })
            ]
          }),
          jsx('span', {
            className: cn(
              'rounded-full px-2 py-0.5 text-xs',
              provider.status === 'ok'
                ? 'bg-(--ui-surface-secondary) text-(--ui-text-secondary)'
                : 'text-(--ui-warning)'
            ),
            children: provider.status.replaceAll('_', ' ')
          })
        ]
      }),
      provider.plan
        ? jsx('span', { className: 'text-xs text-(--ui-text-tertiary)', children: provider.plan })
        : null,
      ...provider.windows.map(window => jsx(QuotaWindow, { window }, window.label)),
      ...provider.details.map(detail =>
        jsx('div', { className: 'text-sm text-(--ui-text-secondary)', children: detail }, detail)
      ),
      provider.message
        ? jsx('div', { className: 'text-sm text-(--ui-warning)', children: provider.message })
        : null
    ]
  })
}

function QuotaPage() {
  const query = useQuotas()
  const providers = query.data?.providers ?? []

  return jsxs('main', {
    className: 'flex h-full flex-col overflow-auto p-6',
    children: [
      jsxs('div', {
        className: 'mb-5 flex items-center justify-between gap-4',
        children: [
          jsxs('div', {
            children: [
              jsx('h1', { className: 'text-xl font-semibold', children: 'Provider Quotas' }),
              jsx('p', {
                className: 'mt-1 text-sm text-(--ui-text-tertiary)',
                children: 'Live account limits from your Hermes gateway'
              })
            ]
          }),
          jsx('button', {
            className: cn(
              'inline-flex items-center gap-2 rounded-md border border-(--ui-stroke-secondary) px-3 py-1.5 text-sm',
              'hover:bg-(--chrome-action-hover) disabled:opacity-50'
            ),
            disabled: query.isFetching,
            type: 'button',
            onClick: () => query.refetch(),
            children: query.isFetching ? 'Refreshing…' : 'Refresh'
          })
        ]
      }),
      query.error
        ? jsx('div', {
            className: 'rounded-md border border-(--ui-stroke-secondary) p-4 text-(--ui-warning)',
            children: `Quota request failed: ${query.error.message ?? query.error}`
          })
        : null,
      query.isLoading
        ? jsx('div', { className: 'text-sm text-(--ui-text-tertiary)', children: 'Loading quotas…' })
        : null,
      jsx('div', {
        className: 'grid gap-4 lg:grid-cols-3',
        children: providers.map(provider => jsx(ProviderCard, { provider }, provider.provider))
      }),
      query.data?.generated_at
        ? jsx('div', {
            className: 'mt-4 text-xs text-(--ui-text-quaternary)',
            children: `Updated ${new Date(query.data.generated_at).toLocaleString()}`
          })
        : null
    ]
  })
}

function QuotaChip() {
  const query = useQuotas()
  const providers = query.data?.providers ?? []
  const warningCount = providers.reduce(
    (count, provider) => count + provider.windows.filter(window => window.warning).length,
    0
  )
  const summary = query.isLoading ? 'quotas…' : warningCount > 0 ? `${warningCount} quota warnings` : 'quotas ok'

  return jsx(Tip, {
    label: 'Open provider quotas',
    children: jsxs('button', {
      className: cn(
        'inline-flex h-full items-center gap-1 px-1.5 text-[0.6875rem] transition-colors',
        'text-(--ui-text-tertiary) hover:bg-(--chrome-action-hover) hover:text-foreground',
        warningCount > 0 && 'text-(--ui-warning)'
      ),
      type: 'button',
      onClick: () => host.navigate('/provider-quotas'),
      children: [jsx(Codicon, { name: 'dashboard', size: '0.7rem' }), jsx('span', { children: summary })]
    })
  })
}

export default {
  id: ID,
  name: 'Provider Quotas',
  register(ctx) {
    rest = ctx.rest
    ctx.registerMany([
      {
        id: 'page',
        area: ROUTES_AREA,
        data: { path: '/provider-quotas' },
        render: () => jsx(QuotaPage, {})
      },
      {
        id: 'nav',
        area: SIDEBAR_NAV_AREA,
        order: 60,
        data: { codicon: 'dashboard', label: 'Provider Quotas', path: '/provider-quotas' }
      },
      {
        id: 'status',
        area: STATUSBAR_AREAS.right,
        order: 70,
        render: () => jsx(QuotaChip, {})
      },
      {
        id: 'open',
        area: PALETTE_AREA,
        data: {
          id: 'provider-quota.open',
          label: 'Open Provider Quotas',
          keywords: ['provider', 'quota', 'usage', 'limits'],
          run: () => host.navigate('/provider-quotas')
        }
      }
    ])
  }
}
