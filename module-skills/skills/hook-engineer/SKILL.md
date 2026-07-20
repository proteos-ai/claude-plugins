---
name: hook-engineer
description: >
  Author Proteos record-lifecycle hooks — Go functions compiled to wasm that
  fire on data-service create/update/delete via the `fn` SDK. before_*
  hooks run synchronously in the write path (validate, mutate, abort with
  fn.UserError); after_* hooks run ASYNCHRONOUSLY post-commit via record
  events (side effects, sync, external calls — at-least-once, so idempotent).
  Covers the six event signatures, the generated domain.<Entity> types
  (pointer rules, typed enums), the host capabilities (records, query, http,
  cache, secrets, storage, connections, log), no-DB-cascade cleanup in
  before_delete, and loop-safe cross-entity sync via a one-shot cache mark.
  Use when filling in a hooks/<slug>/main.go inside a module. Triggers —
  "hook-engineer", "write a hook", "before_create hook", "after_update hook",
  "lifecycle hook", "validate on save", "denormalize", "sync entities",
  "mirror records", "fn.OnBeforeUpdate", "abort a write".
---

# Hook engineer

A **hook** is a Go function, compiled to wasm, that fires around a record
write. Hooks live in a module under `hooks/<slug>/` as a pair: `hook.json`
(the binding) + `main.go` (the handler). This skill is about writing them
correctly. For the surrounding module workflow read **module-builder**; for
the entities the hooks operate on, **domain-modeling**.

## The dispatch model (read this first)

Two fundamentally different execution paths:

- **`before_*`** — **synchronous, pre-commit, in the user's write path.**
  data-service calls function-service over HTTP and waits. Returning an error
  **aborts the write**; the returned record is what persists. Budget: the
  user is waiting — keep it fast (30s hard timeout per hook).
- **`after_*`** — **asynchronous, post-commit, at-least-once.** data-service
  publishes `record.created/updated/deleted` events after commit;
  function-service consumes them and dispatches your hook in a separate
  invocation on a machine token minted for the original actor. A returned
  error causes **redelivery, not write abort** — after-hook failures never
  block the user. Consequences: **handlers must be idempotent** (retries
  happen), they see **committed** state, and they can't mutate the record
  in-flight or abort anything.

**Doctrine:** validation + mutation → `before_*`. Side effects
(denormalization, mirroring, external calls, notifications) → `after_*`, off
the user's write path. Cascade-style cleanup of dependent rows →
`before_delete` (synchronous, so nothing orphans if it fails — see below).

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

From the **module root** (the command reads `module.json` + `go.mod`):

```sh
pro hook init geocode-billing --entity company --event after_update
```

Writes `hooks/<slug>/hook.json` + a compiling `main.go` stub. `hook.json`:

```json
{ "slug": "geocode-billing", "module_slug": "my-domain", "entity": "company", "event": "after_update" }
```

(Field is `entity`, not `entity_slug`.) `--event` accepts all six names.

## The events and their signatures

Register exactly one handler in `init()` with the matching `fn.On*`
generic over the generated `domain.<Entity>` type:

| Event | Register | Handler signature | Path | Can mutate/abort? |
|---|---|---|---|---|
| `before_create` | `fn.OnBeforeCreate[T]` | `func(ctx, record T) (T, error)` | sync, pre-commit | ✅ both |
| `before_update` | `fn.OnBeforeUpdate[T]` | `func(ctx, record T, current T) (T, error)` | sync, pre-commit | ✅ both |
| `before_delete` | `fn.OnBeforeDelete[T]` | `func(ctx, record T) error` | sync, pre-commit | abort only |
| `after_create` | `fn.OnAfterCreate[T]` | `func(ctx, record T) error` | async, post-commit | ❌ (error → retry) |
| `after_update` | `fn.OnAfterUpdate[T]` | `func(ctx, record T, previous T) error` | async, post-commit | ❌ |
| `after_delete` | `fn.OnAfterDelete[T]` | `func(ctx, record T) error` | async, post-commit | ❌ |

Load-bearing facts:

- **`before_create` already has the record `id`** — data-service generates
  the uuid and normalizes values before dispatch. You can create related
  rows pointing back at the new record from `before_create` (`record.Id` is
  `*string`; nil-check).
- **`before_update` gets `(record, current)`** — `record` is the merged
  post-update state (every field, not just the PATCH body), `current` the
  pre-update row. **`after_update` gets `(record, previous)`** — full
  post-commit row + pre-update row. Diff them and act only on the actual
  transition.
- **Hook chains**: multiple active hooks on the same (org, entity, event)
  run as a chain, each seeing the previous one's returned record; no
  ordering knob; the first error aborts (before) / retries (after).

## Anatomy of a handler

```go
package main

import (
	_ "go.proteos.ai/functions-sdk-go/runtime/autoexport"
	"go.proteos.ai/functions-sdk-go/fn"

	"go.proteos.ai/modules/my-domain/gen/domain"
)

func init() {
	fn.OnAfterUpdate[domain.Company](handleAfterUpdate)
}

func handleAfterUpdate(ctx fn.Context, record domain.Company, previous domain.Company) error {
	// idempotent side effect, diffed on the actual transition
	return nil
}

func main() {} // required; the wasm entrypoint
```

Non-negotiables: the `_ ".../runtime/autoexport"` blank import; `func
main() {}`; exactly one `fn.On*` registration per hook package; generated
types imported from `<module-path>/gen/domain` (they exist only after
`pro module build`). Never edit `gen/` — regenerated, CI-guarded by
`pro module check`.

## The generated `domain.<Entity>` types

- Entity slug → PascalCase struct (`company` → `domain.Company`); snake_case
  attribute → PascalCase field (`is_signed` → `IsSigned`).
- **Pointer rule: `is_required && !is_nullable` → bare value; anything else →
  pointer.** A `default_value` does NOT make a field non-pointer; a
  required-but-nullable field is still a pointer. Always nil-check before
  deref: `record.Status != nil && *record.Status == domain.TaskStatusDone`.
- Enums → typed string constants (`domain.TaskStatusDone`), sorted by value.
- `object` attributes → nested structs (`*domain.CompanyBillingAddress`).
- Composite types → lifted structs: `currency` →
  `{Amount string, CurrencyCode string}`; `user` → `{Type, Id string}`;
  `knowledge-text` → `{Id, Content string}` (fresh create may carry only
  `content`, an untouched update only `id`); `file` → `{Id, Name string}`.
- Type map: `number`→`float64`, `integer`→`int64`, `relation`→`string`,
  `datetime` `date-time`→`time.Time` (other formats → `string`), arrays →
  slices.

## Aborting a write — `fn.UserError`

In a `before_*` hook, return an error to abort. `fn.UserError` /
`UserErrorf` messages reach the end user (HTTP 400); plain errors are
internal failures (500-class).

```go
if doc.IsSigned == nil || !*doc.IsSigned {
    return record, fn.UserError("cannot fulfill: the linked document is not signed")
}
```

## Host capabilities

The capability API lives in package `fn` (`go.proteos.ai/functions-sdk-go/fn`) — package-level,
not on ctx. `ctx` carries `Ctx`, `OrgId`, `Source`, and (for HTTP-dispatched
actions) `Headers`/`Header(name)` — nil for hooks. `ctx.Source.Type` ∈
`"person" | "agent" | "api" | "system"`.

```go
import "go.proteos.ai/functions-sdk-go/fn"

// Records (typed, generic)
doc, err := fn.GetRecord[domain.Document](ctx, "document", id)
created, err := fn.CreateRecord[domain.Document](ctx, "document", doc)
updated, err := fn.UpdateRecord[domain.Document](ctx, "document", id, doc)
many, err := fn.ListRecords[domain.Document](ctx, "document", &sdkdata.ListRecordsOptions{...}) // page/sort/bracket filters; returns Many[T]{Meta, Data}
err = fn.DeleteRecord(ctx, "document", id)   // also fn.Records.Delete
resp, err := fn.BatchUpsertRecords(ctx, "document", docs) // batch upsert ([]T); also fn.Records.BatchUpsert for explicit transactions
// Upsert is id-presence based (id exists -> partial-merge update, else create).
// NOT atomic: check resp.Results[i].Status per row (transaction_id = input index).
// No server-side size cap — keep batches modest (~100).

// SQL read model
rows, meta, err := fn.QueryRecords[domain.Document](ctx, `SELECT * FROM document WHERE is_signed = true`)

// Side channels
fn.Log.Info(ctx, "signed", map[string]any{"document_id": id})
val, found, err := fn.Cache.Get(ctx, key)            // org-shared Redis, string values
_ = fn.Cache.Set(ctx, key, v, ttl)                   // ttl 0 = no expiry
resp, err := fn.HTTP.Get(ctx, url, headers)          // headers map[string]string on Get/Post/Put/Patch/Delete
resp, err = fn.HTTP.PostJSON(ctx, url, body)         // no headers param
// resp.StatusCode, resp.Body, resp.JSON(&into), resp.Headers, resp.Header(name)
value, err := fn.Secrets.Read(ctx, "MAPBOX_TOKEN")   // module variable by key — returns the REAL value (secret or not)
url, err := fn.Storage.GenerateDownloadUrl(ctx, fileId, opts)  // short-lived download URL
tok, err := fn.Connections.GetToken(ctx, connectionId)         // connector platform
out, err := fn.Connections.InvokeMethod(ctx, connectionId, method, params)
```

Notes: `fn.HTTP` passes through function-service's SSRF denylist.
`fn.Secrets.Read` returns real values including `is_secret: true` ones —
the redaction of old docs is gone; a hook can read any module variable (the
flag only affects git storage + deploy-overwrite behavior). Error sentinels
via `errors.Is`: `fn.ErrNotFound` (== `fn.ErrNotFound`),
`ErrPermissionDenied`, `ErrBadInput`, `ErrConflict`, `ErrInternal`.

> **Recursion guard.** In a `before_*` hook, mutate `record` and return it —
> never `fn.UpdateRecord` the same record the hook fires on. An `after_*`
> hook that writes its OWN entity re-triggers itself — guard with a diff
> (only write when something actually changes) or the sync mark below.

## Patterns

**Validation guard (before_update, transition-only).** Diff `record` vs
`current`; act only when the field of interest actually changed.

**Uniqueness.** The platform does **not** enforce `is_unique` on records at
all — it's schema metadata (and a relation-target requirement). ANY
uniqueness guarantee, single-attribute included, is a `before_*` hook's job:
query for a conflicting row, `UserError` on hit.

**Side effects (after_*).** Geocode an address, call an external API, mirror
into another entity, notify — in `after_create`/`after_update`, diffed on the
transition, idempotent (retries happen). The user's write already committed;
your latency doesn't block them.

**Bridge/join rows — no DB cascade.** Relations are metadata only:
`on_delete` creates no FK and nothing propagates. Clean up dependent rows in
**`before_delete`** (synchronous — the delete aborts if cleanup fails, so
nothing orphans). NotFound on cleanup is fine — the goal state is "gone":

```go
if err := fn.DeleteRecord(ctx, "task", bridge.TaskId); err != nil && !errors.Is(err, fn.ErrNotFound) {
    return err
}
```

**Cross-entity sync (bidirectional, loop-safe).** When A's hook writes B and
B's hook writes A back, an echo loop forms across the async after-hook
dispatches. Break it with a **one-shot consumed cache mark** layered with a
diff (this is the reference idiom — see
`modules/meetings-task-connector/internal/sync/`):

```go
const guardTTL = 30 * time.Second // lost-echo safety net

// The WRITER marks the peer record before writing it — and does NOT clear
// the mark (the echo arrives later, in a separate async invocation).
func MarkSyncWrite(ctx fn.Context, entity, id string) {
    _ = fn.Cache.Set(ctx, "mymod:sync:"+entity+":"+id, "1", guardTTL)
}

// The peer's hook CONSUMES the mark: on hit it deletes it and skips.
func ConsumeSyncWrite(ctx fn.Context, entity, id string) bool {
    key := "mymod:sync:" + entity + ":" + id
    _, found, err := fn.Cache.Get(ctx, key)
    if err != nil || !found {
        return false
    }
    _ = fn.Cache.Delete(ctx, key)
    return true
}

// In each direction's after_update hook:
func handleAfterUpdate(ctx fn.Context, record domain.Task, previous domain.Task) error {
    if record.Id == nil || ConsumeSyncWrite(ctx, "task", *record.Id) {
        return nil // this write WAS the echo — consumed, stop
    }
    patch, empty := diff(record, previous) // pure, unit-testable
    if empty {
        return nil
    }
    MarkSyncWrite(ctx, "action-item", peerId) // do NOT defer-clear
    _, err := fn.Records.Update(ctx, "action-item", peerId, patch)
    return err
}
```

Two layers, both required: the consumed mark stops the echo; the diff makes
the chain provably terminate. Keep the mapping+diff logic in a pure
`internal/` package with a round-trip-yields-empty-patch test.

## Platform constraints

- **All six events dispatch** — before sync pre-commit, after async
  post-commit at-least-once (idempotency required).
- **Relations: no FK, no cascade** — clean up in `before_delete`.
- **Timeout: 30s per hook** (actions get 1m).
- **`time.Now()`/`time.Sleep` work** (real runtime clock). Historical note:
  records stamped `2022-01-01` predate the clock fix — not your bug.
- **Permissions**: hooks run as the acting user — entities a hook writes need
  the module's `permissions.json` grant or the host call 403s.
- `created_by`/`updated_by` are **platform-stamped** — no audit hook needed.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| Build can't resolve `domain.X` | codegen hasn't run | `pro module build` |
| `nil pointer dereference` | deref'd an optional field | pointer rule: only `is_required && !is_nullable` is bare — nil-check |
| After-hook "runs twice" | at-least-once delivery | make the handler idempotent |
| After-hook error "lost" | async — errors retry/DLQ, never surface to the user | log richly; design for retry |
| Sync hooks ping-pong | writer cleared its own mark / diff missing | one-shot CONSUMED mark + diff (writer never clears) |
| Duplicate rows despite `is_unique` | records aren't uniqueness-enforced | enforce in a `before_*` hook |
| Bridge row dangling after delete | trusted `on_delete: cascade` | delete dependents in `before_delete` |
| User sees a generic 500 | plain `error` from a before-hook | `fn.UserError`/`UserErrorf` |
| Expensive check on every save | didn't diff `record` vs `current`/`previous` | gate on the transition |
| Wasm export missing | removed `autoexport` import or `main()` | restore both |

## Test & ship

```sh
pro module test -- -run TestHook   # go test ./hooks/... ./actions/...
pro module build                   # codegen + wasm → dist/hooks/<slug>.{bundle.json,wasm}
pro module serve                   # live preview: source + compile status per hook
pro module deploy                  # upload (or: pro hook deploy <slug> for just one)
pro functions hooks logs <slug> --follow   # tail after triggering a write
pro functions hooks list|get|activate|deactivate <slug>
```

Verify by actually writing a record — prefer the `proteos` MCP server
(`create_record`/`update_record`, then `get_record` to read the effect back)
over shelling out — and confirm: before-hooks via the mutation/abort,
after-hooks via the side effect + logs (remember they're async — give them a
second).
