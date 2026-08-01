# module-skills

A self-contained skill set — packaged as a **Claude Code plugin** — that lets
Claude Code build **complete, correct Proteos modules from scratch,
interactively with a user**: grounded in the org's knowledge graph, authored
locally with the `pro` CLI, previewed live in the browser, and deployed with
idempotent upserts.

Every skill folder under `skills/` is standalone (its references are
embedded), so each also works as an individual bundle. All facts were verified
against the platform source on 2026-07-09 (metadata-service platform
attributes, function-service dispatch, the control registry, the full `pro`
CLI surface).

## Install

**As a Claude Code plugin** (skills arrive namespaced
`module-skills:<skill>`):

```sh
# local dev (this checkout)
claude plugin marketplace add /path/to/core/plugins
claude plugin install module-skills@proteos

# once plugins/ lives in (or is split into) its own git repo:
claude plugin marketplace add <owner>/<repo>          # or the git URL in the UI
claude plugin install module-skills@proteos
```

The marketplace manifest is [`../.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json)
(the `plugins/` directory is the marketplace root); the plugin manifest is
[`.claude-plugin/plugin.json`](.claude-plugin/plugin.json). Both pass
`claude plugin validate`.

**As zip bundles** (claude.ai skill upload, Anthropic Skills API, or a Proteos
module's `skills/` dir):

```sh
./package-skills.sh
# → dist/skills/<name>.zip   one bundle per skill (SKILL.md inside <name>/)
# → dist/module-skills.zip   the whole plugin
```

## The `pro` binary — a separate layer

Installing the plugin installs **skills**, not the CLI they drive. The `pro`
binary ships only as GitHub Release binaries on the public repo
[`proteos-ai/cli`](https://github.com/proteos-ai/cli) (assets
`pro_<version>_<os>_<arch>.tar.gz`, `.zip` on Windows, + `checksums.txt`;
no `go install`, no Homebrew tap yet).

Every `pro`-driving skill (module-builder, module-creator, hook-engineer,
action-engineer, component-engineer) bundles the same
`scripts/pro-preflight.sh` and runs it before its first `pro` call:

1. detect/install the platform binary (sha256-verified, `~/.local/bin` or
   `PRO_INSTALL_DIR`), or skip if `pro version` already matches;
2. `pro profiles add prod --api-url https://api.proteos.ai` (skip if present)
   + `pro profiles use prod`;
3. `pro login` (Auth0 PKCE, browser) with a clear hand-back to the user when
   headless (`pro login --no-browser` prints the URL); verify `pro whoami`.

Idempotent end to end — re-running a skill with everything in place passes
straight through. Keeping `pro` current also keeps scaffolded modules in SDK
lockstep: `pro module init` pins `go.proteos.ai/functions-sdk-go` to the
CLI's own build version.

## Bundled MCP server

Installing the plugin also registers the unified Proteos platform MCP server
([.mcp.json](.mcp.json)): `proteos`, pointing at
`https://mcp.proteos.ai/v1/all` — every toolset (data, admin, knowledge,
agents, conversations, workflows) over one connection — so module-discovery
can ground in the knowledge graph and the builder can inspect live org
structure without extra setup.

Auth is **OAuth with Dynamic Client Registration** — no token to configure.
On first use Claude Code runs the browser OAuth flow (re-auth anytime with
`/mcp`).

## The skills and how they chain

| Skill | Role | Embedded references |
|---|---|---|
| **module-builder** | THE orchestrator: lifecycle, layout, deploy order, `pro` CLI, the serve/preview loop | `reference.md` (every manifest wire shape), `list/app/menu-reference.md`, `platform.schema.json`, `example-crm-sales/` |
| **module-discovery** | DDD interview before any design; knowledge-graph-grounded when a knowledge MCP is connected; produces the signed-off entity shortlist + review preference | — |
| **domain-modeling** | Entities: DDD → the 13 attribute types, relations, platform attributes | `entity-reference.md`, `platform.schema.json` |
| **page-design** | Page layout trees: elements, controls, conditions, sizing | `page-reference.md`, `platform.schema.json` |
| **hook-engineer** | Go/wasm lifecycle hooks (before sync / after async) | — |
| **action-engineer** | Go/wasm invokable actions (+ public webhooks) | — |
| **component-engineer** | React/TS components in the sandboxed runtime iframe | — |

The intended flow:

```
module-discovery  →  sign-off + capture (knowledge graph or DISCOVERY.md)
      ↓
module-builder    →  pro module init → entities (domain-modeling) → permissions
      ↓               → apps/lists/pages (page-design)/menus
pro module serve  →  SEND THE PREVIEW URL TO THE USER → iterate on their reactions
      ↓               → hooks/actions (hook-/action-engineer) + components (component-engineer)
pro module build  →  pro module deploy → pro meta modules activate → verify in the app
```

## Non-negotiables baked into every skill

- snake_case wire format; kebab-case slugs + enum values; lucide PascalCase icons.
- Platform attributes (`id`, `created_at/updated_at`, `created_by/updated_by`)
  are server-managed — never declared.
- Every new entity ships `permissions.json` grants (or everything 403s).
- Substantive descriptions on every entity/attribute/enum value — the schema
  is read by AI agents.
- Relations enforce `on_delete` (cascade / restrict / set-null) on record
  delete, transactionally — pick it deliberately; `restrict` is not a no-op.
- `before_*` hooks are synchronous (validate/mutate/abort); `after_*` are
  async post-commit at-least-once (side effects, idempotent).
- Preview before deploy: the user approves what they see at the
  `pro module serve` URL, not a JSON diff.
- Tool split: the `pro` CLI owns the module lifecycle (scaffold, add, build,
  serve, deploy); the bundled MCP servers own everything live — knowledge,
  record CRUD, org structure queries — being faster and typed than shell
  round-trips. CLI `pro meta`/`pro data` only as a no-MCP fallback.
