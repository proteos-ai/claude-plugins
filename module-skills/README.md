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
- Relations have no DB cascade — cleanup is a `before_delete` hook.
- `before_*` hooks are synchronous (validate/mutate/abort); `after_*` are
  async post-commit at-least-once (side effects, idempotent).
- Preview before deploy: the user approves what they see at the
  `pro module serve` URL, not a JSON diff.
