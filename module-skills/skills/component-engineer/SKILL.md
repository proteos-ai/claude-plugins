---
name: component-engineer
description: >
  Author Proteos UI components — React/TS blocks bundled to ESM and mounted in
  a sandboxed iframe on record-detail and platform pages. Covers `pro
  components add` scaffolding, esbuild externals (bundled vs provided), how
  page props reach the component as Liquid-resolved SNAPSHOTS (bind scalar
  leaves — objects stringify), the injected authenticated sdk (account,
  agents, data, functions, knowledge, meta, storage), module variables (real
  values — never client-unsafe secrets), props-schema validation, styling via
  design tokens (no CSS imports), auto-resize, navigation + peek, and the
  preview loop: `pro module serve` (whole module) and `pro components preview`
  (isolation). Use when filling in a components/<slug>/index.tsx. Triggers —
  "component-engineer", "write a component", "custom component", "React
  component in a page", "component_slug", "map component", "board component",
  "pro components add", "props-schema".
---

# Component engineer

A **component** is a React/TS block shipped inside a module — bundled to a
single ESM file with esbuild and mounted in a **sandboxed iframe** on a page
(a `component` element on an entity-detail page, a side panel, or a
`"type": "platform"` page like a board/dashboard). Use it when the typed
layout primitives can't express the UI: a map, a chart, a Kanban board, an
embedded widget.

Files: `components/<slug>/` → `index.tsx` (default export) +
`props-schema.json` (prop contract, optional) + `manifest.json` +
per-component `package.json`/`tsconfig.json`. Module workflow →
**module-builder**; the hosting page → **page-design**.

## Hook vs action vs component

- **Hook** — automatic Go/wasm around a write. → hook-engineer.
- **Action** — invokable Go/wasm, server-side authority. → action-engineer.
- **Component** — client-side React, renders/visualizes. **No server-side
  trust** — it runs in the user's browser. Anything needing real secrets or
  privileged writes goes through an action the component invokes.

## CLI preflight

Every command below needs the `pro` binary, a profile pointed at the
platform, and a signed-in session. If this session hasn't verified that yet,
run the bundled script first (idempotent — skips whatever is already in
place):

```sh
sh scripts/pro-preflight.sh    # from this skill's base directory
```

It installs `pro` from GitHub Releases of the public `proteos-ai/cli` repo
(sha256-verified; binaries only — there is no `go install` path), creates and
activates the `prod` profile (`https://api.proteos.ai`), and attempts
`pro login` (Auth0 PKCE, browser). Last line `preflight ok — signed in as …`
→ proceed. `preflight incomplete …` (exit 4) → ask the user to run
`pro login` in their terminal, then re-run. Details + Windows steps: the
script header, and the module-builder skill's step 0.

## Scaffold first

```sh
pro components add <slug>        # from anywhere inside the module tree
pnpm install                     # at the pnpm-workspace root — links @proteos/* deps; build never installs
pro components validate <slug>   # esbuild dry-run: does it bundle?
```

`manifest.json` = `{ slug, module_slug, name, description, is_public? }` — the
builder overwrites `slug`/`module_slug` from the directory + module.json, so
drift can't ship.

> ⚠️ **`is_public: true` makes the compiled bundle world-downloadable**
> (unauthenticated `GET /meta/v1/public/orgs/{orgId}/components/{slug}/bundle`)
> and is required for any component placed on a `type: "public"` page. Only
> set it when the user explicitly asked for a public page/component. On a
> public page the component gets a **restricted sdk** — exactly three
> unauthenticated reaches:
> - `sdk.functions.actions.invokePublic(orgId, slug, params)` against an
>   `is_public` global action (the only path for writes / computed data);
> - read-only records of `public_record_access: ["read"]` entities via
>   `sdk.data.records.list/listPage/get` (org bound automatically;
>   `create`/`update`/`delete`/`batchUpsert` throw) and their definitions via
>   `sdk.meta.entities.get`/`getWithSchema`;
> - `public_access: ["read"]` file downloads via `sdk.storage.files.download` /
>   `publicDownloadUrl(orgId, fileId)`.
>
> Everything else (`account`/`agents`/`knowledge`/authed calls) throws.
> `authToken` is empty there; branch on `useRuntime().isPublic` if a component
> must serve both worlds — the read surface above mirrors the authed method
> names, so `sdk.data.records.list('leads')` runs unmodified in both.
> Full-replacement on deploy: omitting the field flips
> a previously public component back to private (rejected with 409 while a
> public page still references it).

## The runtime contract (read this twice)

The component runs in an iframe, not the host React tree. Handshake:
iframe posts `READY` → host replies `INIT` with `authToken` (raw, no
`Bearer`), `apiBaseUrl`, **`props`** (already Liquid-resolved), and `pageCtx`
(`{record, entity, params}`). The runtime mounts your default export wrapped
in a `QueryClientProvider` + `ErrorBoundary`, and a ResizeObserver auto-sizes
the iframe to your content.

Use the typed hooks from **`@proteos/component-sdk`** (provided external):

```tsx
import { useSdk, useProps, usePageContext, useNavigate } from '@proteos/component-sdk'

const sdk = useSdk()                 // { account, agents, data, functions, knowledge, meta, storage }
const props = useProps<MyProps>()    // Liquid-resolved props (typed)
const { record } = usePageContext()  // SNAPSHOT from mount; undefined on platform pages
const navigate = useNavigate()       // navigate(to) — in-app SPA navigation
// also: useApiBaseUrl(), useAuthToken(), useHostLocation(),
// useFillViewportHeight(), useRuntime() (low-level escape hatch)
```

Never hand-write `window.__PROTEOS_RUNTIME__` typings — it exists for
back-compat only; the hooks are the supported path.

Two consequences:

- **Props and `pageCtx.record` are STATIC snapshots** from INIT — they don't
  update when the record changes, and no host currently pushes
  `DATA_INVALIDATE` (the message type exists; nothing sends it). Anything
  that must stay fresh: fetch it via `sdk.data` + react-query
  (poll/refetch as needed).
- The host re-pushes the auth token only on window focus (`AUTH_REFRESH`) —
  best-effort; the SDK clients handle it for you.

## Record data → Liquid props (the #1 mechanism)

The host resolves the page element's `props` as Liquid against
`{record, entity, params}` before INIT:

```jsonc
// pages/company-detail.json
{ "type": "component", "id": "cmp-map", "component_slug": "company-map",
  "props": {
    "latitude":  "{{ record.billing_address.latitude }}",
    "longitude": "{{ record.billing_address.longitude }}",
    "city":      "{{ record.billing_address.city }}"
  } }
```

**Liquid output is ALWAYS a string.** Two hard rules:

1. **Bind scalar leaves, never whole objects** —
   `"{{ record.billing_address }}"` arrives as `"[object Object]"` and an
   array as its joined elements. Structured props reach the component only
   when the page JSON declares a literal object/array whose scalar leaves
   carry Liquid.
2. **Scalars stringify**: a `number` arrives as `"42"`, a boolean as
   `"true"`. Declare such props `"type": "string"` in props-schema.json and
   coerce in the component (`Number(x)`, `x === "true"`).

## Imports — bundled vs provided

esbuild bundles everything you import EXCEPT the provided externals (shared
with the host via an import map — one React instance):

```
PROVIDED: react, react-dom, @tanstack/react-query, @proteos/ui, @proteos/sdk, @proteos/component-sdk
BUNDLED:  everything else in the component's package.json (leaflet, d3, chart.js, pragmatic-drag-and-drop, …)
```

Add a dep to the component's `package.json` → root `pnpm install` → import
normally. Browser-only (no Node APIs).

**CSS imports do NOT work** — `import 'leaflet/dist/leaflet.css'` fails the
build (single-file ESM output, esbuild can't emit a css file). Style with:
inline styles + design tokens, `<style>` tags (iframe-scoped), or
`@proteos/ui` primitives. A component's own Tailwind classes are NOT compiled
either — the runtime stylesheet covers `@proteos/ui` only.

## The SDK & auth

`useSdk()` = authenticated `@proteos/sdk` clients on the user's token:

```ts
const sdk = useSdk()  // { account, agents, data, functions, knowledge, meta, storage }

await sdk.data.records.listPage('task', { page_size: 200, sort: 'created_at:desc', assignee: userId })
await sdk.data.records.create('task', { title: 'New' })
await sdk.data.records.update('task', id, { status: 'done' })   // PATCH, partial merge
await sdk.data.records.get('task', id); await sdk.data.records.delete('task', id)

const me = await sdk.account.me.get()
const users = await sdk.account.users.listPage({ page_size: 200, default_org_id: orgId })

await sdk.meta.entities.get('task')
await sdk.meta.variables.listPage({ key: 'MAPBOX_PUBLIC_TOKEN', module: 'sales', page_size: 1 })

await sdk.functions.actions.invokeGlobal('recompute-totals', params)
await sdk.functions.actions.invokeEntity('document', recordId, 'mark-as-signed', params)

await sdk.knowledge.nodes.search({ query: 'onboarding', mode: 'hybrid' })
await sdk.knowledge.recordLinks.list({ entity_slug: 'company', record_id: id })
await sdk.storage.files.get(fileId)
```

Options are snake_case (`page_size`, `sort: "field:dir"`); attribute filters
pass flat with bracket operators (`'due_date[lt]': '2026-01-01'`; bare key =
eq; a `user` attribute filters on the id). `knowledge`/`storage` need their
own role grants — a 403 is permissions, not a bug. Pair everything with the
provided react-query (`useQuery`/`useMutation`, optimistic updates) — and
remember nothing invalidates for you.

## Module variables — the API-key rules

```ts
const { data } = useQuery({
  queryKey: ['var', 'MAPBOX_PUBLIC_TOKEN'],
  queryFn: () => sdk.meta.variables.listPage({ key: 'MAPBOX_PUBLIC_TOKEN', module: 'sales', page_size: 1 }),
})
const token = data?.data?.[0]?.value
```

**The variables API returns REAL values — `is_secret: true` included.** There
is no redaction; the flag only controls git storage (`--secret` rows carry no
value in `variables.json`) and deploy-overwrite behavior. Consequences:

- A publishable, client-safe key (Mapbox `pk.*`) → a module variable, read as
  above. Fine.
- A credential that must never reach a browser → **not a module variable at
  all** (any caller with `variables` read gets it). Keep it server-side and
  proxy through an **action** (`fn.Secrets.Read` there) the component
  invokes via `sdk.functions.actions`.

## Navigation, peek, host URL

- `useNavigate()(to)` — client-side host navigation; only relative in-app
  `/`-paths (external URLs ignored by design).
- `navigate(to, { peek: true })` — opens a **platform-page** path
  (`/org/<o>/app/<a>/page/<p>`) in a slide-over peek; other paths fall back
  to full navigation.
- `useHostLocation()` → `{ orgId, appBasePath, pathname }` — parse the host
  route (scope queries to the org, build record links:
  `navigate(`${appBasePath}/record/task/${id}`)`).

## Layout & styling

- **Auto-resize**: don't hard-code outer heights; render natural content.
- **Full-viewport boards**: `100vh` is circular inside an auto-sized iframe —
  use `useFillViewportHeight()` (returns a pinned height or `null`), then
  `flex: 1; min-height: 0; overflow-y: auto` on scrollable columns.
- **Design tokens** ship in the iframe — style with
  `var(--color-surface-2)`, `var(--color-ink-3)`, `var(--radius-lg)`,
  `var(--shadow-rest)`, `var(--font-mono)` etc., or use `@proteos/ui`
  primitives (`Button`, `Badge`, `Avatar`, `Select`, `EmptyState`,
  `Skeleton`) for a native look.
- `fetch()` to external APIs works (no CSP in the runtime iframe); prefer the
  SDK for Proteos calls.
- Errors: the runtime ErrorBoundary renders an in-frame alert + posts
  `ERROR`; still handle loading/empty/error states yourself.

## props-schema.json (optional but keep it)

JSON-Schema-ish contract. Validation is lenient + client-side (top-level
`required` + `properties.<k>.type`; warns + banner, still renders). It's the
documented contract the page author and the preview read — keep it accurate;
remember Liquid-bound scalars are strings.

## Preview loop — three surfaces, use in this order

1. **`pro module serve` (port 5180) — the canonical loop.** The whole module
   renders in the module-preview app: your component appears as its own tab
   (props = schema defaults overlaid by your `mock.json`) AND inside the
   pages that embed it, with the element's Liquid props resolved against a
   preview record. Every save hot-recompiles the bundle (~100ms, in memory)
   and reloads the iframe; build errors surface in the tab. SDK calls hit the
   serve process's mock API: mocked routes answered locally, the rest proxied
   to the real API with the profile token (`--live-api` to bypass).
   Navigation/peek are stubbed with a note.
   **In Claude sessions with the built-in preview tools**, open this in the
   web preview pane (`preview_start` via `.claude/launch.json`, navigate to
   the localhost `open preview →` URL — `pro` ≥ v0.17.x proxies the app
   same-origin) and verify your own render with `preview_snapshot` /
   `preview_screenshot` after each save; component iframes need a moment to
   handshake — a blank screenshot right after reload isn't a failure, retry
   once. See module-builder step 5 for the full pane workflow.
2. **`pro components preview <slug>` (port 5179)** — the component in
   isolation with an interactive props + pageCtx panel. Good for prop-contract
   work. Release binaries ship the embedded runtime.
3. **Deployed** — `pro module build && pro module deploy`; the live
   ComponentFrame adds real navigation, peek, and focus-driven token refresh.
   (Live iframe sandbox: `allow-scripts allow-same-origin
   allow-top-navigation-by-user-activation`.)

Build output: `dist/components/<slug>.js` + `.bundle.json`; deploy POSTs
metadata + bundle + source tar.gz (node_modules/dist excluded) to
metadata-service — idempotent upsert; components deploy after dist
hooks/actions, before skills.

## Mock data — preview-only, author it alongside the component

Two files drive a convincing preview (neither ever deploys):

- **`components/<slug>/mock.json`** —
  `{"props": {...}, "record": {...}, "entity_slug": "..."}`. `props` overlay
  the props-schema defaults in the standalone tab (Liquid-bound scalars are
  strings — mock them as strings). `record` (or, with only `entity_slug`, the
  first row of that entity's mock data) becomes the page-context record.
  Saving it recompiles the bundle so the iframe remounts with the new values.
- **Module-level `mock-data/`** — `mock-data/<entity-slug>.json` (array of
  records) feeds the pages/lists that embed your component AND the mock API
  your SDK calls hit: `sdk.data.records.*` on a mocked entity is answered
  locally with working filters/sort/pagination; writes mutate an in-memory
  copy (file save resets). Responses come in the LIVE wire shape — the
  authored `{id, label}` relation/user values normalize to a bare id string
  (relation) / `{type, id}` (user), so write component code against
  production shapes, never against the label. Stub anything else (e.g.
  action invokes) in `mock-data/api.json`:
  `[{"method": "POST", "path": "/functions/v1/actions/<slug>/invoke", "response": {"result": {...}}}]`
  — path wildcards `*` (one segment) / trailing `**`, first match wins,
  response verbatim, so action stubs MUST wrap in `{"result": ...}`.
  Non-mocked routes pass through to the real API with the profile token.

## Wiring into a page

```jsonc
// entity-detail: side panel is often the right home for a widget
"side_panel": { "content": { "type": "column", "id": "side", "gap": "md", "children": [
  { "type": "component", "id": "cmp-map", "component_slug": "company-map",
    "props": { "latitude": "{{ record.billing_address.latitude }}",
               "longitude": "{{ record.billing_address.longitude }}" } } ] } }

// platform page: the whole screen is the component
{ "slug": "task-board", "type": "platform", "name": "Task Board", "actions": [],
  "layout": { "version": 1, "main": { "type": "column", "id": "main", "gap": "md",
    "children": [ { "type": "component", "id": "cmp", "component_slug": "task-board", "props": {} } ] } } }
```

## Patterns

- **Record visualizer** (map/chart): Liquid leaf props + a bundled lib.
- **Live related view**: `useQuery` + `sdk.data.records.listPage` for
  rollups/timelines the typed `related_list` can't do; refetch on interval or
  after own mutations (nothing invalidates for you).
- **Action launcher**: rich UI gathers input →
  `sdk.functions.actions.invokeEntity/Global` — writes + secrets stay
  server-side.
- **Platform-page board**: no record; org from `useHostLocation()`, data via
  `listPage`, optimistic react-query mutations, `useNavigate` to open cards,
  `useFillViewportHeight` to pin the board.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| `has no default-exported React component` | named export only | `export default function …` |
| Bare import fails to bundle | dep not installed | add to component package.json + root `pnpm install` |
| Two-React / hook errors | bundled your own react / broke externals | import provided packages normally |
| `Cannot import "….css"` build error | CSS import | inline styles / `<style>` / @proteos/ui |
| Prop is `[object Object]` | Liquid-bound a whole object | bind scalar leaves per prop |
| "should be number, got string" warning | Liquid stringifies | declare string + coerce |
| Component shows stale data | props/record are snapshots; DATA_INVALIDATE never sent | fetch via sdk + refetch |
| Secret visible in devtools | put a server-only credential in a variable | don't — proxy via an action |
| Component not found on page | slug mismatch or not deployed | match `component_slug`; build + deploy |
| Props literal `{{ … }}` | bad Liquid path / missing attribute | `{{ record.<snake_case_attr> }}` |
| listPage options ignored | camelCase (`pageSize`) | snake_case wire (`page_size`) |
| Board won't fill viewport | `100vh` in auto-sized iframe | `useFillViewportHeight()` |
| Column won't scroll | missing `min-height: 0` | `flex:1; min-height:0; overflow-y:auto` |
| 403 from sdk call | entity/resource has no role grant | module `permissions.json` |
| Picker shows other orgs' users | no org scope | `default_org_id` from `useHostLocation()` |

## What this skill does NOT cover

- The hosting page/layout → **page-design**. Server-side work → an **action**
  (action-engineer). Module lifecycle/deploy → **module-builder**. Entity
  shape → **domain-modeling**.
