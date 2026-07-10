---
name: module-builder
description: >
  Build a complete Proteos module from scratch, interactively with the user —
  the end-to-end orchestrator. Runs discovery (module-discovery), scaffolds
  with `pro module init`, authors entities (domain-modeling), apps, lists,
  list-views, pages (page-design), menus, permissions, roles, and variables as
  on-disk JSON, adds Go hooks/actions (hook-engineer, action-engineer) and
  React components (component-engineer) when the domain needs behavior, builds
  with `pro module build`, previews live with `pro module serve` — sending the
  preview URL to the user after every meaningful change — and deploys with
  `pro module deploy` once approved. Owns the module lifecycle, on-disk layout,
  deploy ordering, casing rules, and the full `pro` CLI surface. Use when the
  user wants to build a new module or app area, extend one, or preview one.
  Triggers — "build a module", "create a module", "module-builder", "new
  proteos module", "scaffold a module", "build out <domain>", "stand up a new
  app", "preview the module", "serve the module", "deploy the module".
---

# Module builder

A **module** is the unit of authoring and deployment in Proteos: a local
directory of JSON manifests (entities, apps, pages, lists, menus, permissions,
variables), plus — when the domain needs behavior — Go hooks/actions compiled
to wasm and React components bundled to ESM. You build it locally with the
`pro` CLI, preview it live in the browser, iterate with the user, and deploy
the whole thing with idempotent upserts.

This skill is the **orchestrator**. It owns the lifecycle, the layout, the
deploy order, the preview loop, and the CLI. It delegates content to
specialists:

| Need | Delegate to |
|---|---|
| Understanding the domain (BEFORE anything else) | **module-discovery** |
| Entities, attributes, relations | **domain-modeling** |
| A page's `layout` tree | **page-design** |
| Record-lifecycle hooks | **hook-engineer** |
| User-invokable actions | **action-engineer** |
| Custom React components | **component-engineer** |

The exact wire shape of every manifest lives in [reference.md](reference.md);
the deep per-type references (all 13 attribute types, controls, filters,
layout elements) live in each specialist skill's embedded reference file — validate files
against [platform.schema.json](platform.schema.json).
A worked, convention-correct example module is at
[example-crm-sales/](example-crm-sales/).

## The iron rules (violating any of these produces a broken module)

1. **snake_case wire format, everywhere.** Structural JSON keys
   (`entity_slug`, `is_required`, `related_entity_slug`, `visible_when`) AND
   attribute `name` values (`first_name`, `customer_id`, `is_signed`) are
   snake_case. Slugs are **kebab-case** (`purchase-order`). Enum values are
   **kebab-case** (`payment-pending`; canonical codes like `USD`, `DE` are the
   exception). Icons are **lucide PascalCase** (`FileText`, `Users`). A
   camelCase structural key is silently dropped or rejected.
2. **Platform attributes are server-managed — never declare them.** Every
   entity automatically carries `id`, `created_at`, `updated_at`,
   `created_by`, `updated_by` (the last two typed `user`, auto-stamped). The
   server injects the canonical definitions and drops client redefinitions.
   Your `attributes` list = user-defined fields only. Pages/lists/filters may
   still bind to the platform names.
3. **Every new entity needs a `permissions.json` grant** or every record call
   403s — for end users AND the module's own hooks/actions. No exceptions,
   including bridge/join entities.
4. **`attributes` is a full replacement.** Re-deploying an entity with an
   attribute omitted **deletes that attribute and its data**. Menus' `items`
   and page `layout`s replace wholesale too.
5. **Descriptions are non-negotiable.** Every entity, attribute, enum value,
   and relation carries substantive business context — the schema is read by
   AI agents that have no other source. No placeholders.
6. **Relations have NO database cascade.** `on_delete` is advisory metadata.
   If deleting A must clean up B, a `before_delete` hook does it.
7. **No design before discovery sign-off.** Run **module-discovery** first;
   design only a signed-off, captured understanding.
8. **Preview before deploy.** The user approves what they SEE in the served
   preview, not a JSON diff.

## Canonical module layout

`pro module init <slug>` scaffolds the bold entries; everything else you
create by hand or with the scaffold commands noted:

```
<module-slug>/
├── module.json            ← {slug, name, version, dependencies.entities}      [init]
├── go.mod                 ← Go module for hooks/actions (functions-sdk-go)    [init]
├── .gitignore             ← dist/ + .proteos-dev/                             [init]
├── .gitattributes         ← gen/ linguist-generated                        [init]
├── README.md                                                                  [init]
├── DISCOVERY.md           ← signed-off domain understanding                   [module-discovery]
├── entities/              ← <entity-slug>.json per entity                     [init: empty]
├── hooks/                 ← <slug>/{hook.json,main.go}                        [pro hook init]
├── actions/               ← <slug>/{action.json,main.go}                      [pro action init]
├── gen/                ← GENERATED Go types — never hand-edit              [init: empty]
│   ├── cache/             ← peer entities fetched for codegen (commit this)
│   ├── domain/            ← struct per entity (domain.Order, …)
│   └── actions/           ← <Action>Params / <Action>Result structs
├── apps/                  ← <app-slug>.json                                   [you mkdir]
├── pages/                 ← <page-slug>.json (entity-detail OR platform)      [you mkdir]
├── lists/                 ← <list-slug>.json                                  [you mkdir]
├── list-views/            ← <view-slug>.json (saved filters over a list)      [you mkdir]
├── menus/                 ← <menu-slug>.json (sidebar tree under an app)      [you mkdir]
├── components/            ← <slug>/{index.tsx,props-schema.json,manifest.json,
│                             package.json,tsconfig.json}                      [pro components add]
├── permissions.json       ← role→entity grants (REQUIRED per entity)          [pro module add permission]
├── roles.json             ← roles the module defines (optional)               [pro module add role]
├── variables.json         ← module config variables (optional)                [pro module add variable]
└── dist/                  ← GENERATED build output (gitignored)
```

Modules can also ship agent-service resources (`prompts/ tools/ mcp-servers/
agents/ skills/`) and custom connectors (`connectors/<key>/…`) — see
[reference.md](reference.md).

## The workflow

### 0. Preflight

```sh
pro whoami                              # profile + API URL resolve?
pro meta entities list --page-size 1    # token reads?
```

No profile? `pro login` (browser OAuth) or `pro profiles add <name> --api-url
<url>` + `pro set-token`; env overrides `PROTEOS_API_URL`/`PROTEOS_API_TOKEN`
also work. If `pro` is missing entirely, stop and tell the user how to install
it.

### 1. Discover (GATE)

Run **module-discovery**: interview the user, ground in the knowledge graph
when a knowledge MCP is connected, get the playback + entity shortlist
**signed off**, capture it (graph or `DISCOVERY.md`), and record the **review
preference** (data-first vs visual-first). Also collect from the org:

```sh
pro meta entities list -o json    # slugs are ORG-WIDE unique — avoid collisions
pro meta apps list -o json        # match existing conventions
```

### 2. Scaffold

```sh
pro module init <slug> -y          # or interactive; --name "Display Name"
cd <slug>
mkdir -p apps pages lists list-views menus
```

Bump `module.json` `version` as you iterate. `dependencies.entities` stays
`{}` unless a hook/action needs the Go type of an entity owned by ANOTHER
module (then `{"<peer-slug>": "<version>"}` — build fetches it into
`gen/cache/`; the peer module must be deployed first).

### 3. Author entities (delegate to domain-modeling)

One `entities/<slug>.json` per entity, shaped as `CreateEntityRequest` —
the domain-modeling skill's entity-reference.md has
every attribute type (all 13: `string number integer boolean datetime enum
array object relation user currency knowledge-text file`) and their `meta`
shapes. Remember: no platform attributes, full descriptions, snake_case names,
`module_slug` = this module.

**Grant permissions immediately, per entity** (iron rule 3):

```sh
pro module add permission --role admin --entity <slug> --permission read
pro module add permission --role admin --entity <slug> --permission write
pro module add permission --role admin --entity <slug> --permission delete
```

If the module needs its own narrower role: `pro module add role <slug> --name
"…" --description "…"` then grant that role instead/additionally.

### 4. Author the UI (apps → lists → list-views → pages → menus)

Author in dependency order so every reference resolves as you go:

1. `apps/<slug>.json` — `{slug, name, description, icon_slug}` (lucide
   PascalCase icon).
2. `lists/<slug>.json` — `{slug, entity_slug, name, columns[], sorting[],
   filters[]}`; `columns[].attribute` = snake_case attribute names (platform
   names like `created_at` allowed).
   [list-reference.md](list-reference.md).
3. `list-views/<slug>.json` — saved `FilterGroup`s over a list. Optional.
4. `pages/<slug>.json` — the record-detail screen (or a `"type": "platform"`
   dashboard page hosting components). Delegate the `layout` tree to
   **page-design**;
   the page-design skill's page-reference.md.
5. `menus/<slug>.json` — sidebar tree under an app; `items[].type` ∈
   `link|group|entity|page|list`, `reference` = target slug.
   [menu-reference.md](menu-reference.md).

**Validate every file** against
[platform.schema.json](platform.schema.json)
(each type maps to a `$def`; e.g. `#/$defs/createEntityRequest`) before
previewing — a file that fails schema renders wrong or is rejected on deploy.

### 5. Preview live + iterate with the user (the core loop)

```sh
pro module serve        # port 5180; falls back to a free port if taken
```

Serve watches the module and prints two URLs — **send the second one to the
user as a clickable link** and keep serve running in the background:

```
▶ module data → http://127.0.0.1:5180
▶ open preview → <app-url>/module-preview/?server=http%3A%2F%2F127.0.0.1%3A5180
```

- `--app-url` defaults from the profile (`api.*` → `app.*`; localhost →
  `http://localhost:5173`). If derivation fails it warns — pass `--app-url`
  explicitly.
- The preview renders with the **real platform renderers**: entities as the
  schema designer, pages with a deterministic sample record, lists as the real
  table, components **live** in the runtime iframe (authenticated SDK calls
  via the profile token), hooks/actions as Go source + build status.
- **Every save hot-updates the preview** over SSE: manifest edits re-render in
  place; component edits recompile in ~100ms; hook/action edits rebuild wasm
  in the background and the preview flips a green `compiled` / red
  `build failed` badge showing the **verbatim compiler error**.
- Honor the review preference: **data-first** → walk entities in the preview
  sidebar first, then pages/lists; **visual-first** → lead with pages/lists,
  open entity tabs only on request.
- Run ONE serve per module. Re-invoking stacks a second server on a fallback
  port — kill the previous background task first.
- Iterate: user reacts in the browser → you edit files → preview follows.
  Surface non-obvious trade-offs (embed vs relate, tabs vs sections) as you
  go. **Deploy only after the user approves the preview.**

### 6. Behavior — hooks, actions, components (only if the domain needs it)

Scaffold **from the module root** (`hook init`/`action init` require cwd =
module root; `components add` works anywhere inside the tree):

```sh
pro hook init <slug> --entity <entity> --event before_create   # or before_update|before_delete
pro action init <slug> --scope entity --entity <entity>        # or --scope global
pro components add <slug>                                      # then: pnpm install at repo root
```

- Hook handler → **hook-engineer**. ⚠️ Only `before_*` events are dispatched
  by the platform today; the CLI accepts `after_*` but they never fire —
  author everything as before-hooks.
- Action `params`/`returns` (Attribute[] in `action.json`) + handler →
  **action-engineer**. Wire an entity action to a page toolbar button via the
  page's `actions[]` (`"action": "<action-slug>"`).
- Component (React over the injected SDK, Liquid props) →
  **component-engineer**. Reference from a page `component` element
  (`component_slug`).

First hook/action in a repo-workspace module? Add it to the Go workspace once
from the repo root: `go work use ./modules/<slug>` — otherwise build fails
with "not one of the workspace modules listed in go.work". The generated
`main.go` imports `gen/domain` types that **don't exist until the first
`pro module build`** (codegen) — build before expecting the editor to resolve.

### 7. Build

```sh
pro module build [--verbose]   # peer-entity cache → functions-codegen → wasm + esbuild + skill bundles → dist/
pro module test                # go test ./hooks/... ./actions/...
pro module check               # CI guard: gen/ matches manifests (network-free, uses gen/cache)
```

Pure-metadata modules (no hooks/actions/components/skills) deploy without
build. Anything in `dist/` requires build first. `pro module dev` = watch +
rebuild without the preview server (serve already rebuilds — prefer serve).

### 8. Deploy & activate

```sh
pro module deploy --dry-run    # print the plan, no HTTP
pro module deploy              # idempotent upsert of every resource
pro meta modules activate <slug>
```

Deploy order: module.json → entities → apps → pages → lists → list-views →
menus → variables → roles → permissions → connectors → dist (hooks, actions,
connector-methods, components, skills) → prompts → mcp-servers → tools →
agents. Failed steps are **deferred and retried** after the rest of the pass —
intra-module relation ordering self-heals; re-running converges. The
resource's slug comes from its **filename** (dir name for hooks/actions/
components); `module_slug` is stamped from module.json.

`activate` on an already-active module returns a benign HTTP 500 ("already
activated") — ignore it.

### 9. Verify for real

Schema-valid ≠ correct. After deploy:

- `pro meta entities get <slug> -o json` — attributes landed.
- Open the app in the web client: menu shows, list loads, record page renders.
- Create/update a record to fire hooks; press the page action button; check
  `pro functions hooks logs <slug> --follow` / `pro functions actions logs
  <slug>`.
- `pro meta variables list` — no secret got blanked.

Don't claim success without exercising the deployed behavior.

## Module config files (`pro module add …`)

Never hand-write these three; the CLI creates on first add, then appends +
dedupes (duplicates error):

| File | Command | Row shape |
|---|---|---|
| `permissions.json` | `pro module add permission --role <r> --entity <e> --permission <read\|write\|delete>` | `{role_slug, entity_slug, permission}` |
| `roles.json` | `pro module add role <slug> [--name] [--description]` | `{slug, name, description}` |
| `variables.json` | `pro module add variable --key <K> [--value <v>] [--secret]` | `{key, value, is_secret}` |

Variables trap: `is_secret` is a **handling flag, not read protection** — the
variables API serves the REAL value to hooks (`fn.Secrets.Read`), components
(`sdk.meta.variables`), and any caller with the `variables` read permission
(including a browser). `--secret` means: value never stored in git (set it
out-of-band after deploy), and deploy never overwrites the stored value
(`--secret` + `--value` together is rejected). A credential that must never
reach a client does NOT belong in a module variable — keep it server-side
(e.g. behind an action). Re-deploying an EMPTY non-secret `value` over a
populated one blanks it (unchanged values are skipped) — verify with
`pro meta variables list`.

## Updating an existing module

- `pro module pull` — overwrite local manifests with the deployed state of
  everything the module owns (refuses on a dirty git tree unless `--force`;
  `--prune` deletes de-owned files). Manifests only — Go/TSX source and skill
  bundles are not stored server-side.
- `pro module clone <slug> [dir]` — reconstruct a module directory from a
  deployed env (not immediately buildable: no source files).
- To change one attribute on a deployed entity: edit `entities/<slug>.json`
  (the FULL attribute list) and re-deploy — never send a partial list.

## Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `json: unknown field "…"` on deploy | camelCase structural key | snake_case every key |
| Field renders `Unknown attribute · X` | `field.attribute` ≠ entity attribute name (casing drift) | match the snake_case name exactly |
| Records 403 / list empty / hook can't write | new entity has no role grant | `pro module add permission` × read/write/delete (step 3) |
| Hook/action missing after deploy | `dist/` stale or absent | `pro module build`, then deploy |
| Hook bound to `after_*` never fires | platform dispatches `before_*` only | rebind to a `before_*` event |
| Build: "not one of the workspace modules in go.work" | module dir not in root go.work | `go work use ./modules/<slug>` once |
| Codegen can't resolve `domain.X` | peer entity not in `dependencies.entities` / peer not deployed | add the pin + deploy the peer first |
| Menu icon renders placeholder | icon not lucide PascalCase | `FileText`, `Users`, `TrendingUp` |
| Slug collision on deploy | slugs are org-wide (module doesn't namespace) | pick a distinct slug |
| Preview URL 404s | web app doesn't host `/module-preview/` | deployed env, or run the web dev server + `--app-url` |
| Second serve on a weird port | previous serve still running | kill the old background task first |
| Bridge rows orphaned after parent delete | assumed `on_delete` cascades | delete dependents in a `before_delete` hook |
| Sensitive key leaked to the browser | any `variables` value (secret or not) is readable client-side | never store server-only credentials as module variables |

## Command quick reference

```sh
pro whoami · pro login · pro profiles list|use|add
pro module init <slug> [-y] [--name <n>]
pro module add permission|role|variable …
pro hook init <slug> --entity <e> --event before_create|before_update|before_delete   # cwd = module root
pro action init <slug> --scope entity|global [--entity <e>]                           # cwd = module root
pro components add <slug> · pro components validate <slug> · pro components preview <slug>  # component-only preview, port 5179
pro module build [--verbose] · pro module test · pro module check
pro module serve [--port 5180] [--app-url <origin>]     # LIVE PREVIEW — send URL to the user
pro module deploy [--dry-run] · pro meta modules activate|deactivate <slug>
pro module pull [--prune] [--force] · pro module clone <slug> [dir]
pro functions hooks|actions list|get|activate|deactivate|logs <slug> [--follow]
```

## What this skill does NOT do

- **Records/data** (creating customers, orders): that's the `pro data` surface
  — out of scope; the module builds structure, not rows.
- **Users, orgs, assigning users to roles**: platform administration. A module
  DOES ship role definitions + entity grants (`roles.json`,
  `permissions.json`) — creating users and putting them IN roles is not module
  content.
- **Deep content authoring**: entities → domain-modeling; layouts →
  page-design; Go/TS internals → the engineer skills.
