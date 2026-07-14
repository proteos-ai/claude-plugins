---
name: action-engineer
description: >
  Author Proteos actions — user-invokable Go functions compiled to wasm that
  run a domain operation via the `fn` SDK. Covers the scopes (entity —
  invoked against one record — and global; connector_method exists but is
  connector-service territory), the typed handler signatures, the
  params/returns schemas (entity-attribute shape) that codegen into
  <Action>Params/<Action>Result structs, the host surface, ctx.Headers for
  webhook verification, public actions (is_public), surfacing user-facing
  failures with fn.UserError, and wiring an action to a page toolbar
  button. Use when filling in an actions/<slug>/main.go and its action.json
  inside a module. Triggers — "action-engineer", "write an action",
  "invokable action", "entity action", "global action", "page button action",
  "fn.RegisterAction", "action params", "public action", "webhook action".
---

# Action engineer

An **action** is a user-invokable operation — a Go function compiled to wasm
that the platform exposes for explicit invocation (a page toolbar button, an
API call, a public webhook), as opposed to a hook which fires automatically on
a write. Actions live under `actions/<slug>/` as `action.json` (binding + I/O
schema) + `main.go` (handler). For the module workflow read
**module-builder**; for the entities, **domain-modeling**; for the page
button, **page-design**.

## Hook vs action

- **Hook** = automatic, around a write (validate/mutate before; side effects
  after). → **hook-engineer**.
- **Action** = explicit: the user or a client *invokes* it to perform a named
  operation — multiple records, external systems, one atomic gesture.

A multi-step thing the user deliberately triggers is an action.

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

From the **module root**:

```sh
pro action init mark-as-signed --scope entity --entity document
pro action init recompute-totals --scope global
```

`--scope entity` requires `--entity`; `global` forbids it. Writes
`actions/<slug>/{action.json,main.go}`. `action.json`:

```json
{
  "slug": "mark-as-signed",
  "module_slug": "my-domain",
  "scope": "entity",
  "entity": "document",
  "name": "Mark as signed",
  "params": [],
  "returns": []
}
```

> **`slug` is the dispatch key** (the segment in the invoke URL, org-unique);
> `name` is a free display label. The button text users see is the page's
> `actions[].label`, separate again.
>
> A third scope exists — `connector_method` — synthesized by the build for
> `connectors/<key>/methods/<name>/` and dispatched only by connector-service
> (`POST /functions/v1/connector-methods/:slug/invoke`). You'll see it in
> `pro functions actions list`; don't author it via `pro action init`.

## Scopes and signatures

| Scope | Register | Handler signature | Invoked |
|---|---|---|---|
| `entity` | `fn.RegisterAction[P,R]` | `func(ctx, recordId string, params P) (R, error)` | against one record |
| `global` | `fn.RegisterGlobalAction[P,R]` | `func(ctx, params P) (R, error)` | without record context |

Entity-scoped actions receive the `recordId` they were invoked on — load it
with `fn.GetRecord`. Global actions operate across the org (batch
recompute, import, webhook receiver).

## `params` / `returns` — the typed contract

Arrays of the **same `Attribute` shape as entity attributes** (snake_case
names, `type`, `label`, `description`, `is_required`, `meta` — all 13 types).
`params` = the request body (object keyed by param names); `returns` = the
result body. Codegen emits `actions.<Action>Params` / `actions.<Action>Result`.

```json
"params": [
  { "name": "signature_type", "type": "enum", "label": "Signature Type",
    "description": "electronic routes an e-sign flow; manual records a paper signature.",
    "is_required": true, "is_nullable": false,
    "meta": { "values": [
      { "value": "electronic", "label": "Electronic", "description": "Routed through the e-sign provider." },
      { "value": "manual",     "label": "Manual",     "description": "Wet-ink signature recorded after the fact." } ] } },
  { "name": "signature_id", "type": "string", "label": "Signature ID",
    "description": "Upstream signing-system id, if the provider issued one.",
    "is_required": false, "is_nullable": false }
],
"returns": [
  { "name": "document_id", "type": "string",  "label": "Document ID", "description": "Id of the signed document.", "is_required": true, "is_nullable": false },
  { "name": "is_signed",   "type": "boolean", "label": "Is Signed",   "description": "Always true on success.",     "is_required": true, "is_nullable": false }
]
```

Enum values follow the platform convention: **kebab-case** (`electronic`),
canonical external codes excepted. All names snake_case; booleans
`is_`/`has_`/`can_`.

Codegen: slug → PascalCase prefix (`mark-as-signed` →
`actions.MarkAsSignedParams`); pointer rule `is_required && !is_nullable` →
bare value, else pointer; enum params → typed constants. Never edit
`gen/actions/` — change `action.json` and rebuild.

## Anatomy of a handler

```go
package main

import (
	"errors"

	_ "go.proteos.ai/functions-sdk-go/runtime/autoexport"
	"go.proteos.ai/functions-sdk-go/fn"
	"go.proteos.ai/functions-sdk-go/fn"

	"go.proteos.ai/modules/my-domain/gen/actions"
	"go.proteos.ai/modules/my-domain/gen/domain"
)

const documentEntity = "document"

func init() {
	fn.RegisterAction[actions.MarkAsSignedParams, actions.MarkAsSignedResult](handleMarkAsSigned)
}

func handleMarkAsSigned(ctx fn.Context, recordId string, params actions.MarkAsSignedParams) (actions.MarkAsSignedResult, error) {
	var result actions.MarkAsSignedResult

	doc, err := fn.GetRecord[domain.Document](ctx, documentEntity, recordId)
	if err != nil {
		if errors.Is(err, fn.ErrNotFound) {
			return result, fn.UserErrorf("document %q does not exist", recordId)
		}
		return result, err
	}
	if doc.IsSigned != nil && *doc.IsSigned {
		return result, fn.UserError("document is already signed")
	}

	signed := true
	doc.IsSigned = &signed
	updated, err := fn.UpdateRecord[domain.Document](ctx, documentEntity, recordId, doc)
	if err != nil {
		return result, err
	}
	if updated.Id != nil {
		result.DocumentId = *updated.Id
	}
	result.IsSigned = true
	return result, nil
}

func main() {}
```

Non-negotiables (same as hooks): the `autoexport` blank import, `func
main() {}`, one registration per package, generated types exist only after
`pro module build`.

## Host surface & identity

Identical to hooks (see **hook-engineer** for the full list: records, query,
HTTP w/ headers + SSRF denylist, cache, secrets — real values, storage
download URLs, connections, log). Action-specific:

- **`ctx.Headers` / `ctx.Header(name)`** — inbound HTTP headers are flattened
  into the action envelope. This is the canonical way a webhook action
  verifies a caller (`ctx.Header("x-webhook-token")`), not a param.
- `ctx.Source.{Id,Type}` — the invoking principal (`person|agent|api|system`).
  Use it to auto-fill "current user did X" params.
- An action writing the record it operates on is **normal** — it re-triggers
  that record's hooks, usually desired.
- **Timeout: 1 minute** per invocation.
- Relations have no cascade; new entities the action writes need
  `permissions.json` grants; `time.Now()` works.

## User-facing failures

`fn.UserError`/`UserErrorf` for anything the invoking user should see;
plain errors are internal. Actions are interactive — good messages matter.

## Wiring to the UI

Entity actions become page toolbar buttons via the page's `actions`:

```json
"actions": [ { "label": "Mark as signed", "icon": "PenLine", "action": "mark-as-signed" } ]
```

`icon` lucide PascalCase; `action` = the action slug. In the `pro module
serve` preview the button renders with a "runs in the live app" note —
actions execute only against a deployed module.

### Invocation contract (API callers / tests)

- Entity: `POST /functions/v1/entities/:entity/records/:recordId/actions/:slug/invoke`
- Global: `POST /functions/v1/actions/:slug/invoke`
- Public (global only): `POST /functions/v1/public/orgs/:orgId/actions/:slug/invoke`
- Request body = the `params` object directly (no envelope). **Response is
  enveloped: `{ "result": { …returns… } }`.**
- Toggle flags: `PATCH /functions/v1/actions/:slug` with
  `{ "is_active": bool, "is_public": bool }`.

### Public actions (`is_public`)

A **global** action can be exposed unauthenticated (webhooks, public forms)
with `"is_public": true` in `action.json` (ignored for entity scope). The
gate is only `is_public` + active; anyone can POST. A public invocation runs
as the action's **creator** on a freshly minted machine token (creator's
org + user), so host calls authorize against the creator's real permissions —
the trust is in the action code, not the caller. Therefore a public action
MUST validate its inputs and verify the caller — canonically a token/HMAC
**header** via `ctx.Header(...)` compared against a module variable (see the
reference webhook: `modules/google-connector/actions/receive-calendar-webhook`).

⚠️ Only set `"is_public": true` when the user **explicitly asked** for an
unauthenticated surface (a webhook, a public page's data source) — never as a
convenience. On `type: "public"` pages, public actions are the only path for
**writes and computed/aggregated data** (invoked via `invokePublic`, no
caller verification possible there) — plain read-only record access is
better served by setting the entity's `public_record_access: ["read"]` (see
domain-modeling) instead of writing a passthrough action. Whatever a public action returns is
effectively world-readable: expose the minimal read, never a generic query
passthrough.

## Patterns

- **Single-call state transition** — bundle "set flag + fill object" so hooks
  fire once and the UI makes one round-trip.
- **Auto-fill from caller identity** — fall back to `ctx.Source` when a param
  is omitted.
- **Cross-record orchestration (global)** — iterate
  `fn.ListRecords`/`QueryRecords`, apply, accumulate counts into `Result`.
- **External system call** — `fn.Secrets.Read` the token,
  `fn.HTTP.PostJSON`, persist with `fn.UpdateRecord`.
- **Webhook receiver (public global)** — verify `ctx.Header`, parse params,
  write records; return quickly.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Build can't resolve `actions.XParams` | codegen hasn't run | `pro module build` |
| `scope=entity requires "entity"` on deploy | missing `entity` | set it (or scope=global) |
| `recordId` arg unexpected | `RegisterAction` used for global | `RegisterGlobalAction` |
| nil deref on a param | optional params are pointers | nil-check |
| User sees 500, not your message | plain `error` | `fn.UserError` |
| Button does nothing | page `action` ≠ action slug | match slugs |
| Caller can't parse the response | expected bare returns | it's `{ "result": … }` |
| Webhook spoofable | trusted params for auth | verify a secret header via `ctx.Header` |

## Test & ship

```sh
pro module test -- -run TestAction
pro module build                      # → dist/actions/<slug>.{bundle.json,wasm}
pro module serve                      # preview: source + compile status
pro module deploy                     # or: pro action deploy <slug>
pro functions actions logs <slug> --follow
pro functions actions list|get|activate|deactivate <slug>
```

Verify by invoking for real — the page button or the invoke endpoint — and
confirm the records changed and `{ "result": … }` came back as specified.
