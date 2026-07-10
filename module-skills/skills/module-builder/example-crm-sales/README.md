# Example — `crm-sales`

A complete, convention-correct module to pattern-match against. It models
**customers** and the **orders** they place, with a record-detail page, two
lists, a saved segment, an app, and a sidebar.

```
crm-sales/
├── module.json
├── entities/   customer.json · order.json      ← author FIRST (pages/lists resolve entities by slug)
├── apps/       sales.json
├── lists/      active-customers.json · open-orders.json
├── list-views/ my-active-customers.json
├── pages/      customer-detail.json             ← Overview → tabs (Orders related_list) → collapsed Shipping
└── menus/      sales-nav.json
```

Every file is the exact `Create<Kind>Request` payload that `pro module deploy`
consumes and the `pro module serve` preview renders. Each validates against
[`../platform.schema.json`](../platform.schema.json):

```sh
npx ajv validate -c ajv-formats -s ../platform.schema.json --spec=draft2020 \
  -r "../platform.schema.json#/\$defs/createEntityRequest" -d entities/customer.json
```

Note the entities declare **no platform attributes** — `id`, `created_at`,
`updated_at`, `created_by`, `updated_by` are server-managed; lists and pages
still bind to them (`created_at` column).

## Sample data shapes (preview)

The serve preview auto-samples records deterministically; when you hand-curate
a record, these are the value shapes (keys = snake_case attribute names;
`owner` is a `user` value with an inline label for offline rendering;
`annual_revenue.amount` is a **string**):

```json
{
  "id": "rec_8842",
  "name": "North Star Logistics",
  "email": "ops@northstar.io",
  "status": "active",
  "industry": "Freight & logistics",
  "annual_revenue": { "amount": "2840000.00", "currency_code": "USD" },
  "owner": { "id": "usr_dana", "label": "Dana Reyes" },
  "is_priority": true,
  "created_at": "2026-05-04T14:32:00Z",
  "shipping_address": { "address_line_1": "120 Harbor Way", "city": "Oakland", "postal_code": "94607", "country": "US" }
}
```

## What this example deliberately omits

To ship it for real, add a `permissions.json` granting a role
read/write/delete on `customer` and `order` (**required** for any new entity —
`pro module add permission …`), then `pro module deploy` +
`pro meta modules activate crm-sales`. See the module-builder skill.
