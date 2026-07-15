# Module manifest reference — exact wire shapes (snake_case)

The authoritative JSON shape for every file `pro module deploy` reads. Each
maps 1:1 onto a Go request struct in `packages/go/model/meta/api/` (or
`.../functions/api/`). **All structural keys are snake_case. All attribute
`name` values are snake_case.** Unknown/camelCase keys are dropped or rejected.

File → struct → deploy endpoint:

| File | Struct | Deployed via |
|---|---|---|
| `module.json` | `metaapi.DeployModuleRequest` | Modules.UpsertBySlug |
| `entities/<slug>.json` | `metaapi.CreateEntityRequest` | Entities.UpsertBySlug |
| `apps/<slug>.json` | `metaapi.CreateAppRequest` | Apps.UpsertBySlug |
| `pages/<slug>.json` | `metaapi.CreatePageRequest` | Pages.Upsert |
| `lists/<slug>.json` | `metaapi.CreateListRequest` | Lists.UpsertBySlug |
| `list-views/<slug>.json` | `metaapi.CreateListViewRequest` | ListViews.UpsertBySlug |
| `menus/<slug>.json` | `metaapi.CreateMenuConfigurationRequest` | MenuConfigurations.Upsert |
| `variables.json` | module variables upsert | Variables (per row) |
| `roles.json` | role upsert | Roles (per row) |
| `permissions.json` | role→entity grant | RoleEntityPermissions (per row) |
| `hooks/<slug>/hook.json` | `functionsapi.DeployHookRequest` | (built → dist → Hooks.Deploy) |
| `actions/<slug>/action.json` | `functionsapi.DeployActionRequest` | (built → dist → Actions.Deploy) |
| `components/<slug>/manifest.json` | component pipeline | (built → dist → component upsert) |
| `prompts/<key>.json` | `agentapi.CreatePromptRequest` | Prompts.UpsertByKey |
| `mcp-servers/<key>.json` | `agentapi.CreateMcpServerRequest` | McpServers.UpsertByKey |
| `tools/<key>.json` | `agentapi.CreateToolRequest` | Tools.UpsertByKey |
| `agents/<key>.json` | `agentapi.CreateAgentRequest` | Agents.UpsertByKey |
| `skills/<dir>/SKILL.md` (+ files) | bundle pipeline | (built → dist → Skills.Deploy) |

> The `slug` in each file is **overwritten by the filename** at deploy time
> (the deployer derives it from `<slug>.json`). Keep them equal anyway for
> sanity. Hook/action/component slugs come from the **directory name**.
>
> **agent-service resources** (`prompts/ mcp-servers/ tools/ agents/`) key off the
> filename (`<key>.json`); a **skill's** key comes from its `SKILL.md` frontmatter
> `name`, not the directory name. They deploy **last** (after `dist/*`), in the
> order prompts → skills → mcp-servers → tools → agents, because agents reference
> the others and `kind=action` tools reference module actions. Every one is an
> idempotent server-side upsert, so the deferred-retry walk converges agent↔sub-agent
> chains. The agent-suite permission slugs (`agents`, `prompts`, `skills`, `tools`,
> `mcp-servers`) are platform entities already granted to the `admin` role on org
> bootstrap — grant them to a custom role via `permissions.json` if needed.

---

## module.json — `DeployModuleRequest`

```json
{
  "slug": "my-domain",
  "name": "My Domain",
  "version": "0.1.0",
  "dependencies": { "entities": {} }
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**; org-wide unique |
| `version` | string | **required**; bump as you iterate (`build` requires it) |
| `name` | string | display name |
| `description` | string | optional |
| `dependencies.entities` | `{slug: version}` | peer entities to fetch for codegen; `{}` if none |

---

## entities/<slug>.json — `CreateEntityRequest`

```json
{
  "slug": "document",
  "name": "Document",
  "is_remote": false,
  "module_slug": "my-domain",
  "description": "What this represents in the business, its lifecycle, who creates/consumes it. 2–4 sentences.",
  "title_template": "{{ name }}",
  "attributes": [ /* Attribute[] — see below */ ]
}
```

| key | type | notes |
|---|---|---|
| `slug` | string | **required**; singular, kebab-case; org-wide unique; immutable |
| `name` | string | human label |
| `is_remote` | bool | `true` → sourced from an external system |
| `public_record_access` | string[] | operations ALL records are publicly exposed for. Only `["read"]` accepted today → world-READABLE list + get-one + entity definition; `write`/`delete` reserved. Empty `[]` = private (default); full-replacement (omit = resets). ⚠️ express user permission only — see domain-modeling's entity-reference.md |
| `module_slug` | string | this module's slug |
| `description` | string | business context (non-negotiable; read by AI agents) |
| `title_template` | string | Liquid, e.g. `"{{ first_name }} {{ last_name }}"` |
| `attributes` | `Attribute[]` | **full replacement** on re-deploy — never send a partial list |

### Attribute (shared by entity attributes, object children, array items, action params/returns)

```json
{
  "name": "customer_id",
  "type": "relation",
  "label": "Customer",
  "description": "The customer this document belongs to.",
  "is_required": true,
  "is_nullable": false,
  "is_unique": false,
  "is_read_only": false,
  "default_value": null,
  "meta": { /* type-specific; see below */ }
}
```

| key | type | notes |
|---|---|---|
| `name` | string | **snake_case** data-key; unique within the entity; booleans get `is_`/`has_`/`can_` |
| `type` | enum | `string` `number` `integer` `boolean` `datetime` `enum` `array` `object` `relation` `user` `currency` `knowledge-text` `file` |
| `label` | string | UI label (Title Case) |
| `description` | string | business meaning |
| `is_required` | bool | must be supplied on create |
| `is_nullable` | bool | can be set null after create (independent of `is_required`) |
| `is_unique` | bool | unique constraint |
| `is_read_only` | bool | server-managed; hidden from create/patch flows (`id`, `created_at`, …) |
| `default_value` | any | optional default |
| `meta` | object | type-specific (below); omit for `boolean` |

> **Platform attributes are server-managed — do NOT declare them.** Every
> entity automatically carries five canonical attributes: `id` (string PK),
> `created_at` / `updated_at` (datetime), `created_by` / `updated_by`
> (`user`-typed, auto-stamped; system writes carry the `platform` sentinel).
> The server injects them first on create AND update and **drops any
> client-supplied attribute with a colliding name** — the canonical definition
> always wins (`packages/go/model/meta/platform-attributes.go`,
> `EnsurePlatformAttributes`). Your `attributes` list contains ONLY the
> user-defined fields. Pages/lists/filters may still bind to the platform
> names (`created_at`, `created_by`), and `id` is the default relation target.

### `meta` by type

**string** — `StringAttributeMeta`
```json
{ "min_length": 1, "max_length": 200, "pattern": "^[A-Z]", "format": "email" }
```
`format` ∈ `email` `uri` `uuid` `hostname` `ipv4` `ipv6`.

**number / integer** — `NumberAttributeMeta`
```json
{ "minimum": 0, "maximum": 100, "exclusive_minimum": 0, "exclusive_maximum": 100, "multiple_of": 0.01 }
```

**datetime** — `DatetimeAttributeMeta` (`format` **required**)
```json
{ "format": "date-time", "minimum": "2020-01-01T00:00:00Z", "maximum": "2030-12-31T23:59:59Z" }
```
`format` ∈ `date-time` `date` `time` `duration`.

**enum** — `EnumAttributeMeta`. Enum *values* are domain strings (any case the
business uses — `DE`, `ELECTRONIC`, `payment_pending`); only the structural
keys are snake_case.
```json
{ "values": [
  { "value": "lead",        "label": "Lead",        "description": "Initial capture — name + email, no qualifying call yet." },
  { "value": "customer",    "label": "Customer",    "description": "First invoice paid; switches into post-sales workflows." }
] }
```

**object** — `ObjectAttributeMeta` (embedded value object; recursive `Attribute[]`)
```json
{ "attributes": [
  { "name": "address_line_1", "type": "string", "label": "Address Line 1", "is_required": false, "is_nullable": false },
  { "name": "postal_code",    "type": "string", "label": "Postal Code",    "is_required": false, "is_nullable": false }
] }
```

**array** — `ArrayAttributeMeta` (`items` is a nested `Attribute`)
```json
{ "items": { "name": "tag", "type": "string", "label": "Tag", "is_required": false, "is_nullable": false },
  "min_items": 0, "max_items": 20, "items_must_be_unique": true }
```

**user** — `UserAttributeMeta` (reference to a platform user; the record value
is a composite `{ "type": "person|agent|api", "id": "<user-id>" }` UserRef
stored as JSONB — clients may send a bare id string, the server normalizes to
`type: "person"`)
```json
{ "description": "The account owner responsible for renewals." }
```

**currency** — `CurrencyAttributeMeta` (monetary amount; the record value is
`{ "amount": "2840000.00", "currency_code": "USD" }` — **`amount` is a decimal
STRING**, a JSON number is rejected with HTTP 400)
```json
{ "default_currency_code": "EUR", "allowed_currency_codes": ["EUR", "USD", "GBP"] }
```

**knowledge-text** — `KnowledgeTextAttributeMeta` (long-form text stored as a
knowledge-service node; the record holds `{ "id": "<node-id>" }` and reads are
enriched with the content. Use for rich notes/bodies agents should also reach
via the knowledge graph)
```json
{ "description": "Long-form meeting notes, editable by agents via the knowledge MCP." }
```

**file** — `FileAttributeMeta` (reference to a storage-service file; the record
holds `{ "id": "<file-id>", "name": "<filename>" }`)
```json
{ "description": "The signed contract PDF." }
```

**relation** — `RelationAttributeMeta` (many-to-one; FK-style ref on the host)
```json
{ "related_entity_slug": "customer",
  "related_attribute": "id",
  "predicate": "belongs to",
  "description": "A document belongs to one customer.",
  "on_delete": "restrict" }
```
`on_delete` ∈ `cascade` `restrict` `set-null` (`set-null` incompatible with
`is_required: true`). `related_attribute` must be `id` or a `is_unique: true`
target. FK attribute name convention: `<related_slug>_id` (`customer_id`).
Many-to-many → an explicit join entity.

> ⚠️ **`on_delete` is advisory metadata — there is NO database foreign key and
> NO automatic cascade.** Deleting the referenced record does not delete, null,
> or restrict the referrer at the DB level. If a delete should propagate
> (remove a child, clear a bridge row), a `before_delete` **hook** must do it
> explicitly (see hook-engineer). Treat `on_delete` as documentation of intent,
> not an enforced constraint.

---

## apps/<slug>.json — `CreateAppRequest`

```json
{
  "slug": "documents",
  "name": "Documents",
  "description": "Manage document templates and collected customer documents.",
  "icon_slug": "FileText"
}
```
`icon_slug` is **lucide PascalCase** (`FileText`, `Users`, `TrendingUp`).

---

## lists/<slug>.json — `CreateListRequest`

```json
{
  "slug": "documents",
  "entity_slug": "document",
  "name": "Documents",
  "columns": [
    { "attribute": "name",       "label": "Name",    "width": 280 },
    { "attribute": "type",       "label": "Type",    "width": 200 },
    { "attribute": "is_signed",  "label": "Signed",  "width": 90 },
    { "attribute": "created_at", "label": "Created", "width": 160 }
  ],
  "sorting": [ { "attribute": "created_at", "direction": "desc" } ],
  "filters": []
}
```
`columns[].attribute` and `sorting[].attribute` are **entity attribute names**
(snake_case). `direction` ∈ `asc` `desc`. `filters` is `FilterGroup[]` (below).

---

## list-views/<slug>.json — `CreateListViewRequest`

A saved filter on top of a list.

```json
{
  "slug": "signed-documents",
  "list_slug": "documents",
  "name": "Signed documents",
  "columns": [],
  "sorting": [],
  "filters": [
    { "logical_operator": "and",
      "elements": [ { "field": "is_signed", "operator": "eq", "value": "true" } ],
      "groups": [] }
  ]
}
```

### FilterGroup / FilterElement (also `visible_when` / `read_only_when` on pages)

```json
{ "logical_operator": "and",          // "and" | "or"
  "elements": [ { "field": "<attribute_name>", "operator": "eq", "value": "true" } ],
  "groups": [ /* nested FilterGroup */ ] }
```
- `field` is a snake_case attribute name.
- `value` is **always a string** (the server coerces): booleans → `"true"`/`"false"`; `in`/`not_in` → pipe-joined `"a|b|c"`.
- `operator` ∈ `eq` `ne` `gt` `gte` `lt` `lte` `in` `not_in` `contains` `starts_with` `ends_with` `empty` `not_empty`.

---

## menus/<slug>.json — `CreateMenuConfigurationRequest`

```json
{
  "slug": "documents",
  "name": "Documents navigation",
  "app_slug": "documents",
  "is_default": true,
  "items": [
    { "id": "collected", "order": 0, "label": "Collected", "type": "group", "icon": "FolderClosed", "reference": "", "children": [
      { "id": "documents", "order": 0, "label": "Documents", "type": "list", "icon": "FileText", "reference": "documents", "children": [] }
    ] }
  ]
}
```

`MenuItem`:

| key | type | notes |
|---|---|---|
| `id` | string | stable within the menu |
| `order` | int | sort order among siblings |
| `label` | string | display |
| `type` | enum | `link` `group` `entity` `page` `list` |
| `icon` | string | lucide PascalCase |
| `reference` | string | target slug (list slug / page slug / entity slug); `""` for `group` |
| `children` | `MenuItem[]` | nesting |

`items` is a **whole-tree replacement** on re-deploy.

---

## pages/<slug>.json — `CreatePageRequest`

```json
{
  "slug": "document-detail",
  "entity_slug": "document",
  "name": "Document detail",
  "actions": [ { "label": "Mark as signed", "icon": "PenLine", "action": "mark-as-signed" } ],
  "layout": { "version": 1, "main": { /* LayoutElement */ }, "side_panel": { /* optional */ } }
}
```

**Two page kinds:**
- **Entity-detail page** (above): `entity_slug` set, bound to one entity's
  records. `entity_slug` is **immutable** after create.
- **Platform page**: a standalone screen with **no `entity_slug`** and
  `"type": "platform"` instead — a dashboard, a Kanban board, a report. It
  renders outside any record context and typically hosts one or more
  `component` elements that fetch their own data via the injected SDK. Bind it
  from a menu with `{ "type": "page", "reference": "<page-slug>" }`.

```json
{ "slug": "task-board", "type": "platform", "name": "Task Board", "actions": [],
  "layout": { "version": 1, "main": { "type": "column", "id": "main", "gap": "md",
    "children": [ { "type": "component", "id": "cmp", "component_slug": "task-board", "props": {} } ] } } }
```

`actions[].action` is a free-form string the route resolves (commonly an action
slug). `actions[].icon` is lucide PascalCase. Design the `layout` tree with
**page-design** (snake_case throughout); the element/prop
quick-reference:

| element / prop (snake_case wire) | notes |
|---|---|
| `type`: `row` `column` `section` `tabs` `field` `related_list` `component` `divider` `text` | discriminator |
| CommonProps: `id` `visible_when` `read_only_when` `width` `height` `grow` `shrink` `align` `responsive` | on every element |
| row/column: `gap` (`xs`/`sm`/`md`/`lg`) `align` `justify` `children`; row also `allows_wrap` | |
| section: `title` `description` `is_collapsible` `default_collapsed` `content` | |
| tabs: `tabs[]` (`id` `label` `icon` `visible_when` `content`) `default_tab_id` | |
| field: `attribute` `label`(null hides) `description` `placeholder` `is_read_only` `is_required` `empty_display` `control` `control_props` | `attribute` = snake_case data-key; dot-path into objects (`signature.type`) |
| related_list: `related_entity_slug` `via_attribute` `list_slug` | `via_attribute` = the relation attr on the related entity pointing back |
| component: `component_slug` `props` | |
| text: `variant` (`heading`/`subheading`/`body`/`caption`/`callout`) `content` | |
| side_panel: `width` `is_sticky` `content` | optional right rail |

Minimal valid layout:
```json
{ "version": 1, "main": {
  "type": "column", "id": "main", "gap": "md", "children": [
    { "type": "section", "id": "sec-1", "title": "Identity", "content": {
      "type": "column", "id": "col-1", "gap": "sm", "children": [
        { "type": "field", "id": "f-name", "attribute": "name" }
      ] } }
  ] } }
```

---

## hooks/<slug>/hook.json — `DeployHookRequest`

```json
{ "slug": "validate-fulfillment", "module_slug": "my-domain", "entity": "required-document", "event": "before_update" }
```
`event` ∈ `before_create` `before_update` `before_delete` `after_create`
`after_update` `after_delete`. Note the field is **`entity`** (not
`entity_slug`). Authoring the `main.go` → **hook-engineer**.

---

## actions/<slug>/action.json — `DeployActionRequest`

```json
{
  "slug": "mark-as-signed",
  "module_slug": "my-domain",
  "scope": "entity",
  "entity": "document",
  "name": "mark-as-signed",
  "params": [ /* Attribute[] — same shape as entity attributes */ ],
  "returns": [ /* Attribute[] */ ]
}
```
`scope` ∈ `entity` (requires `entity`) `global` (omit `entity`). `params` and
`returns` are `Attribute[]` (snake_case names) and drive codegen of
`<Action>Params` / `<Action>Result` structs. Authoring the `main.go` →
**action-engineer**.

---

## components/<slug>/manifest.json (+ props-schema.json, index.tsx)

```json
{ "slug": "welcome-banner", "module_slug": "my-domain", "name": "Welcome Banner",
  "description": "Hero greeting built from the record's name." }
```
`props-schema.json` is a JSON-Schema object describing the component's props.
`index.tsx` is a React component compiled by the CLI's component pipeline into
`dist/components/<slug>.bundle.json`. Referenced from a page via a `component`
element (`component_slug`).

---

## permissions.json — role→entity grants (root of the module)

**REQUIRED whenever the module adds entities.** A new entity is in no role's
grant list, so every record call returns 403 until granted — including calls
made by the module's own hooks/actions. A flat array of grants, deployed
idempotently (re-granting an existing grant is a no-op).

**Author with the CLI** (creates the file on first add, appends + dedupes;
run from anywhere in the module tree):

```sh
pro module add permission --role admin --entity task --permission read
pro module add permission --role admin --entity task --permission write
pro module add permission --role admin --entity task --permission delete
```

→ `permissions.json`:

```json
[
  { "role_slug": "admin", "entity_slug": "task", "permission": "read" },
  { "role_slug": "admin", "entity_slug": "task", "permission": "write" },
  { "role_slug": "admin", "entity_slug": "task", "permission": "delete" }
]
```

| key | type | notes |
|---|---|---|
| `role_slug` | string | `--role`; the role being granted (commonly `admin`) |
| `entity_slug` | string | `--entity`; the entity to grant access to |
| `permission` | enum | `--permission` ∈ `read` `write` `delete` (grant all three to fully manage) |

Grant every entity the module adds, **including internal bridge/join
entities** — sync hooks that create those rows run as the acting user and will
401/403 without the grant. This is the reproducible alternative to ad-hoc
`pro account roles permissions assign` calls.

---

## roles.json — roles the module defines (optional)

If the module needs its own role (beyond the built-in `admin`), declare it
here and grant it in `permissions.json`. Author with the CLI:

```sh
pro module add role task-viewer --name "Task Viewer" --description "Read-only access to the task board."
```

→ `roles.json` (row shape `{ slug, name, description }`; `--name` defaults to a
prettified slug; no `org_id` is stored — roles are org-portable):

```json
[
  { "slug": "task-viewer", "name": "Task Viewer", "description": "Read-only access to the task board." }
]
```

Most modules don't need this — they grant the existing `admin` role. Add a
role only when you want a distinct, narrower grant set.

---

## variables.json — module variables / config (optional)

Module-scoped key/value config read by hooks/actions (`fn.Secrets.Read`) and
components (`sdk.meta.variables`). Author with the CLI:

```sh
pro module add variable --key MAPBOX_PUBLIC_TOKEN --value "pk.eyJ..."   # readable; value stored in git
pro module add variable --key STRIPE_SECRET_KEY --secret               # key only; value set out-of-band
```

→ `variables.json` — the row shape is exactly **`{ key, value, is_secret }`**
(there is **no `description` field**; `--secret` rows carry no `value`):

```json
[
  { "key": "MAPBOX_PUBLIC_TOKEN", "value": "pk.eyJ...", "is_secret": false },
  { "key": "STRIPE_SECRET_KEY", "value": "", "is_secret": true }
]
```

| key | type | notes |
|---|---|---|
| `key` | string | `--key`; SCREAMING_SNAKE by convention |
| `value` | string | `--value`; omitted (empty) for `--secret` rows |
| `is_secret` | bool | `--secret` sets `true`; see the trap below |

> ⚠️ **What `is_secret` does — and does NOT do.** `is_secret: true` is a
> *handling* flag, not read protection: the real value is stored in the DB and
> **served in cleartext by the variables API** — hooks (`fn.Secrets.Read`)
> AND components (`sdk.meta.variables`) read the actual value, as does any
> caller holding the `variables` read permission (including a browser).
> What `--secret` buys you: the value is never stored in `variables.json`
> (git hygiene — set it out-of-band with `pro meta variables` after deploy),
> and **deploy never overwrites a stored secret value**. (`--secret` +
> `--value` together are rejected.)
> **Consequence:** module variables are fine for client-safe/publishable keys
> and for tokens your hooks/components must read — but a credential that must
> never reach a browser does NOT belong in a module variable at all; keep it
> server-side (e.g. behind an action that makes the call). Also:
> **re-deploying a non-secret variable with an empty `value` blanks the stored
> value** — never deploy a placeholder-empty `value` over a populated one;
> unchanged values are skipped. Verify with `proteos` `list_variables` (or `pro meta variables list`).

---

# agent-service resources (AI agents)

The four JSON dirs + the skills bundle dir ship a module's AI-agent configuration.
All are keyed by an **immutable kebab `key`** and deployed via an idempotent
server-side upsert. They deploy **last** (after `dist/*`), in the order
**prompts → skills → mcp-servers → tools → agents**. Single-object responses are
bare JSON (no `{data}` envelope). Authoring deeper logic — skill bundles →
**(Anthropic Agent-Skills shape)**; tool bindings → an action via **action-engineer**
or an MCP server tool.

## prompts/<key>.json — `agentapi.CreatePromptRequest`

```json
{
  "key": "assistant-system",
  "name": "Assistant system prompt",
  "description": "Base persona for the support assistant.",
  "body": "You are a concise, friendly support assistant for {{ company }}.",
  "inputs": [ /* Attribute[] — same shape as entity attributes; the Liquid placeholders */ ]
}
```

| key | type | notes |
|---|---|---|
| `key` | string | **required**; immutable; = filename |
| `name` | string | **required** |
| `body` | string | **required**; Liquid-templated instruction text |
| `inputs` | `Attribute[]` | placeholders the template expects (snake_case names) |

> Prompts are **versioned**. A re-deploy whose `body`+`inputs` are unchanged forks
> **no** new version (server-side hash dedup); a changed body forks exactly one.

## mcp-servers/<key>.json — `agentapi.CreateMcpServerRequest`

```json
{
  "key": "web-search",
  "name": "Web Search",
  "url": "https://mcp.example.com/mcp",
  "auth": { "type": "none" }
}
```

| key | type | notes |
|---|---|---|
| `key` | string | **required**; immutable; = filename |
| `name` | string | **required** |
| `url` | string | **required**; the MCP server endpoint |
| `auth.type` | string | `none` \| `bearer` \| `oauth` |

> **Config only — never put secrets in the manifest.** A `bearer` token or an
> `oauth` client/connection is established **out-of-band** (Agent Studio UI). A
> re-deploy is **credential-preserving**: it updates name/url/auth.type but never
> wipes a stored token / OAuth client. (OAuth tokens never live on the row at all.)

## tools/<key>.json — `agentapi.CreateToolRequest`

```json
{
  "key": "search-the-web",
  "name": "search_the_web",
  "description": "Search the public web for a query.",
  "kind": "mcp",
  "binding": { "server_key": "web-search", "tool_name": "search" }
}
```

`kind` + `binding` are a discriminated union:

| kind | binding shape | references |
|---|---|---|
| `action` | `{ "action_key": "<slug>" }` | a function-service action (often this module's) |
| `mcp` | `{ "server_key": "<key>", "tool_name": "<name>" }` | an `mcp-servers/` entry |
| `client` | *(omit `binding`)* | host-provided; no binding |

> `name` is the wire name the model calls (`tool_use.name`). Input/output schemas
> are **resolved on read** from the binding source — never authored here. Update is
> full-replace (the kind↔binding coupling makes a partial patch ambiguous).

## agents/<key>.json — `agentapi.CreateAgentRequest`

```json
{
  "key": "support-assistant",
  "name": "Support Assistant",
  "description": "Front-line support persona.",
  "system_prompt": "assistant-system",
  "model_config": { "model_id": "claude-opus-4-8" },
  "skills": ["greeting"],
  "tools": ["search-the-web"],
  "subagents": [],
  "mcp_servers": ["web-search"],
  "is_org_default": false
}
```

| key | type | notes |
|---|---|---|
| `key` | string | **required**; immutable; = filename |
| `name` | string | **required** |
| `system_prompt` | string | a **prompt key** (resolved against `prompts/`), not raw text |
| `model_config.model_id` | string | the LLM model id (e.g. `claude-opus-4-8`) |
| `skills` / `tools` / `subagents` / `mcp_servers` | `string[]` | keys of the respective resources (must exist) |
| `is_org_default` | bool | at most one agent per org may be the default |

> Every referenced key (prompt/skill/tool/mcp-server/sub-agent) must resolve at
> deploy time — which is why agents go last. Sub-agent chains converge over the
> deferred-retry walk.

## skills/<dir>/SKILL.md (+ files) — bundle pipeline → `Skills.Deploy`

```
skills/
  greeting/
    SKILL.md        # frontmatter `name:` is the canonical skill KEY (kebab)
    reference.md    # any supporting files travel in the bundle
```

`pro module build` tar.gz's `skills/<dir>/` into `dist/skills/<dir>.tar.gz` +
`.bundle.json`; deploy uploads it. The skill **key + name + description come from
the bundled `SKILL.md` frontmatter** (the directory name is only organizational).
Skills are **versioned**; a re-deploy of an unchanged bundle (same checksum) creates
no new version. Bundle layout follows the Anthropic Agent-Skills shape (`SKILL.md`
at the bundle root).
