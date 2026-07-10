---
name: module-discovery
description: >
  Run domain discovery for a Proteos module like a seasoned Domain-Driven-Design
  architect — elicit the ubiquitous language, actors, commands and events,
  aggregates and their boundaries, lifecycles, invariants, and relationships by
  asking the right questions. Ground the session in the org's knowledge graph
  when a Proteos knowledge MCP server is connected (research FIRST, ask only
  what the graph doesn't answer, capture the signed-off understanding back);
  fall back to a written DISCOVERY.md in the module when it isn't. Produces the
  signed-off understanding + entity shortlist that feeds module-builder and
  domain-modeling. Use before designing any Proteos module, when scoping a new
  app/domain, or when interviewing a stakeholder about their business.
  Triggers — "module-discovery", "understand the domain", "discovery session",
  "scope this use case", "what are we building", "domain discovery", "before we
  design", "interview the stakeholder", "capture the requirements".
---

# Module discovery

Before anything is modeled, the domain must be understood — deeply, in the
business's own words. This skill runs that discovery the way a **senior
Domain-Driven-Design architect** would: draw out the ubiquitous language, the
actors and their jobs, the events and the rules, the aggregates and their
boundaries — by asking the right questions and listening hard.

It pairs with **module-builder**: discovery produces the *understanding*;
the builder (with **domain-modeling** and **page-design**) turns it into
entities, pages, and lists that render in a live preview.

## Prime directive

**Understand before you model.** A great domain model is 80% listening and
asking the right question at the right moment. You are done with discovery when
you can describe every candidate aggregate in a paragraph and every attribute
and state in a sentence **without inventing anything** — sourced either from
prior knowledge or from an answer the user gave you. Until then, keep asking.

---

## Step 0 — Check your knowledge surfaces

Two situations, handle both gracefully:

- **A Proteos knowledge MCP server is connected** (tools like `search_nodes`,
  `get_node_meta`, `read_node_content`, `get_neighbors`, `create_node`,
  `link_nodes` — typically named `proteos-knowledge*`): the org's knowledge
  graph is your durable memory. Use Step 1 (research first) and Step 4a
  (capture to the graph).
- **No knowledge MCP**: skip graph research; interview from scratch and capture
  the signed-off understanding to **`DISCOVERY.md` at the module root**
  (Step 4b) so the design phase and future sessions inherit it.

Also check the org's live structure regardless — existing entities carry
conventions and collision risks:

```sh
pro meta entities list -o json     # existing slugs + conventions
pro meta apps list -o json         # existing apps the new module sits beside
```

---

## Step 1 — Research the graph first (when connected)

Arrive informed. Search → open → traverse, anchored in time:

- **Search** for the company, domain, people, and concepts the user raises —
  `search_nodes` (hybrid), with `is_valid_at = today` for present-tense
  questions.
- **Open** a hit with `get_node_meta` (metadata + labels + depth-1 neighborhood
  in one call, without the body). Skim large bodies with `get_node_outline`,
  read only the relevant range with `read_node_content`.
- **Traverse** with `get_neighbors` — knowledge is spread across linked nodes.
  Follow `derived_from` / `relates_to` / `supports` / `references`.
- **Respect certified/authoritative nodes** (e.g. a `certified` label) —
  company-wide definitions are ground truth; don't re-litigate or edit them.

Come out with a written mental model of **what you already know** and **what's
missing, stale, or ambiguous** — that gap list is your interview agenda. Never
ask the user something the graph already answers; verify it instead.

---

## Step 2 — Interview like a DDD architect (the heart)

Lead with what you already know; spend your questions on the gaps and the
*why*. Organized by DDD lens, not as a flat form:

- **Ubiquitous language.** "What do you call this?" Capture the exact nouns and
  verbs (deals, shipments, matters, "closing", "dispatch") and use *their*
  words back — never rename their concepts into generic ones. Note where one
  word means two things.
- **Actors & jobs-to-be-done.** "Who does this? What are they trying to get
  done? What does a good day look like for them?" Roles and tasks become
  screens.
- **Commands & events (event-storming style).** "Walk me through what happens,
  start to finish. What kicks it off? What has to be true before that can
  happen? What does the system record when it does?"
- **Aggregates & boundaries.** "Does a *line item* ever exist without its
  *order*? If I delete the order, what happens to it? What always changes
  together?" This finds aggregate roots — the most important modeling decision.
- **Entities vs value objects.** "Does this thing have an identity you track
  over time, or is it just a value describing something else?" Identity →
  entity; interchangeable value → embedded object.
- **Lifecycles & state.** "What states does this move through? What triggers
  each transition? What's allowed or blocked in each state? Can it go
  backwards?" Closed state sets become enums with a documented reason per
  value.
- **Relationships & cardinality.** "One customer, many orders — or can an order
  span customers? Is the reference optional? Which side owns the link?"
- **Invariants & business rules.** "What must always be true? What can never
  happen? What would a new hire get wrong?" These later become hooks/validation
  — capture them now.
- **Automation wishes.** "What should happen automatically when a <thing> is
  created or changes state? What would you never want to do by hand again?"
  These become hooks and actions.
- **Edges, scale & reporting.** The "except when…", the volume (dozens or
  millions), and what the business must *report* on — these shape lists/views.

### How to ask well

- **Open-ended first, always.** Begin each lens with a question that can't be
  answered in one word: *"Walk me through what happens when…"*. A good
  discovery turn is **mostly the user talking**. If your first discovery
  message is a multiple-choice form, you have already failed.
- **Directional pickers, sparingly.** Reserve option-pickers for bounded forks
  (scale, scope of a first cut) — after you've heard the story, never as the
  opener.
- **The 3 whys.** Probe the reason behind every field, state, and rule — up to
  three levels: *"Why do you track that? → Why does that matter? → What breaks
  if it's wrong?"* Stop at a business truth.
- **Mirror the language.** Play their terms back: "So a *matter* belongs to one
  *client*, holds many *documents*, and moves intake → active → closed —
  right?" Correction is signal.
- **Surface trade-offs out loud.** When a call is genuinely open (embed vs
  relate, one aggregate vs two, enum vs lookup entity), name it, recommend, let
  them weigh in.
- **Know when to stop.** When you can describe the model back faithfully and
  they agree, discovery is done.

### Question bank (open-ended archetypes)

```
- "Tell me about <thing> — what is it, in your words?"
- "Walk me through the life of a <thing>, start to finish."
- "What's important for you to know about a <thing>? What do you look at first?"
- "When does a <thing> begin to exist, and when is it done?"
- "What has to be true before <event> can happen?"
- "What should happen automatically when a <thing> is created / changes state?"
- "What must never happen? What would a new hire get wrong?"
- "Who needs this, and what are they trying to get done?"
- (3 whys) "Why do you track that?" → "Why does that matter?" → "What breaks if it's wrong?"
```

### Ask the review preference (during scoping)

Ask how they want to review the design and record the answer — it drives how
module-builder presents the live preview:

> **How would you like to review the design as I build it?**
> - **Data-first (schema):** I show each **entity** (fields, types,
>   relationships) first, we get the model right, then I build the screens.
>   Best if you think in data.
> - **Visual-first (screens):** we iterate directly on the **pages and lists**
>   in the live preview — the actual screens your team will use. The data model
>   is still built underneath, just not led with. Best if you'd rather react to
>   what users see.

---

## Step 3 — Playback & sign-off (a GATE — no design before this passes)

Before authoring a single entity, page, or list, **play the model back in plain
language and get explicit sign-off:**

1. **What I heard** — the ubiquitous language, actors, lifecycles, key
   relationships and rules, in *their* words.
2. **My impression** — what you'd recommend in or out of a first cut, and the
   open questions that remain.
3. **Proposed entities** — a high-level shortlist: **names and one-line
   descriptions ONLY.** No attributes, no enums, no JSON, no pages.
4. **Behavior** — the automation wishes you'll implement as hooks/actions,
   one line each.
5. **How we'll work** — restate the review preference (data-first vs
   visual-first).

Ask the user to confirm or correct. **Do not proceed until they sign off.** If
scope changes later, revise the playback and re-confirm.

---

## Step 4 — Capture the understanding (a GATE — before any design)

### 4a. With a knowledge MCP (preferred)

Persist the *entire* signed-off understanding immediately after sign-off.
Reuse the org's node conventions (list labels first, reuse existing ones —
commonly `discovery`, `use-case`, `platform`, plus a topical label):

- **A discovery-session node** — one per session: title
  `Discovery — <Company/Domain> <topic> (Session, YYYY-MM-DD)`, a summary,
  and a provenance header (who you spoke with, the date, which agent captured
  it). Set `valid_from`.
- **Use-case / domain nodes** — one node per coherent thing: an
  aggregate/entity, a workflow, a lifecycle, a key business rule, the
  automation wishes.
- **An entity-shortlist node** — the signed-off entity names + one-line
  descriptions + the chosen review preference. This is the bridge object the
  design phase expands.
- **Links**: use-case/shortlist nodes `derived_from` the session node;
  `relates_to`/`references` the existing nodes you found in Step 1. Enrich
  existing nodes rather than duplicating; supersede (never overwrite) when
  understanding replaces an old fact.

### 4b. Without a knowledge MCP

Write **`DISCOVERY.md`** at the module root with the same content: provenance
header, ubiquitous language glossary, per-aggregate paragraphs, lifecycles,
invariants + automation wishes, the entity shortlist, and the review
preference. Commit it with the module — it's the model's "why" for every
future session.

---

## Step 5 — Hand off to module-builder

With sign-off + capture done, **module-builder** scaffolds the module and runs
the design/preview loop: aggregates → entities (**domain-modeling**), states →
enums, screens → pages/lists (**page-design**), behavior → hooks/actions,
review via `pro module serve`. Discovery decides *what and why*; the builder
decides *how it's shaped and shown*.

## Hard rules

- **Research before you ask** (when a graph is available). Never re-ask what's
  already known; verify and move on.
- **Never fabricate.** Everything captured is sourced from the graph or from an
  answer the user gave. Missing = `unknown` or an open question.
- **Open before closed.** No multiple-choice form as the opening move.
- **No design before sign-off.** Never author an entity, page, or list until
  the playback + entity shortlist is confirmed.
- **Capture before design.** Persist the understanding (graph or DISCOVERY.md)
  immediately after sign-off.
- **Ask the review preference** and record it.

## What this skill does NOT do

- Design entities/pages/lists — **module-builder** + **domain-modeling** +
  **page-design**.
- Build behavior — it *captures* invariants and automation wishes; implementing
  them is **hook-engineer** / **action-engineer**, later.
- Bulk source ingestion (docs/transcripts into the graph) — that's an ingestion
  pipeline concern, not live discovery.
