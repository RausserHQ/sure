# Liability correctness: design and implementation handoff

Status: accepted. The user confirmed all nine live design choices and the shared
understanding, and authorized a documentation-only PR without further checks.

Decision ticket: [Choose the smallest design that satisfies liability correctness](https://github.com/RausserHQ/sure/issues/24).
Map: [Wayfinder: plan end-to-end liability correctness from main](https://github.com/RausserHQ/sure/issues/19).

## Basis and boundaries

Design baseline: `e426559ccbdadee0e342ff90172bc4b6aa89d9db`, checked on
2026-09-26 Pacific time. Compared with the researched baseline
`437c317606497d713a6683f8d8c9a64a17602efd`, only `CONTEXT.md` and
`.codegraph/.gitignore` changed. Application behavior is unchanged.

This plan specifies how to meet the contracts settled in
[Define liability quantities and truthful historical balances](https://github.com/RausserHQ/sure/issues/22#issuecomment-5851674530)
and [Define liability reporting and transfer meaning](https://github.com/RausserHQ/sure/issues/23#issuecomment-5851832668).
Those tickets remain the canonical product decisions; the examples here make
their implementation consequences explicit.

The [independent reference resolution](https://github.com/RausserHQ/sure/issues/26#issuecomment-5852369877)
establishes the classification and Loan arithmetic defects and the checked
bounded principal case. An interest-inclusive provider liability is indicated;
its exact dated component equation remains unverified. This design does not
depend on that equation, a universal lender allocation order, or a new importer
sign rule. The [current-code research](https://github.com/RausserHQ/sure/blob/705b9b3e459177841651bb56cbc643fbaf8db08a/docs/research/ms-liability-current-state.md)
supplies the broader code, fork, and upstream inventory.

Scope is Loan, CreditCard, OtherLiability, and the related entries and reporting
paths needed to make those liabilities correct. Preserve unrelated asset and
investment conventions. Implementation, backfill, production migration,
deployment, provider collection, and household repair remain later work.
All examples below are synthetic and use no transformed household records.

## Chosen approach

Retain Account, Entry, Transaction, Transfer, Valuation, and the recurring
obligation models. Attach evidence, interpretations, and allocations instead of
turning transaction kinds or cash splits into a second meaning they cannot hold.
Use one shared liability calculation and reporting contract across all readers.

The live choices made so far are:

1. Account editors may make explicit, structured declarations without mandatory
   attachments. Record author, source or reason, scope, and revisions.
2. Preserve an interpretation whose support changes, but require review before
   using its invalidated conclusions. Recalculate unaffected conclusions normally.
3. Extend existing records with evidence and allocations; do not introduce a
   general journal/posting system.
4. Permit reusable, account-specific interpretations with explicit conditions,
   dates, and revisions. Record which revision produced every accepted result.
5. Require coverage for the requested quantity and interval before reconstructing
   history. Transaction completeness alone does not prove liability completeness.
6. Show spending and debt funding separately. Combine planning amounts only when
   the overlap is established; do not build a cash-reservation system in this effort.
7. Unmatching explicitly resolves whether entries describe separate events or an
   uncertain relationship. Show the impact and preserve independently supported
   components.
8. Display the dated last supported balance when the current value is unavailable.
   It does not become today's contribution to complete net worth.
9. Keep established account credits separate from owed debt and available credit.
   A credit contributes positively to net worth when its meaning is supported.

## Why existing primitives need these extensions

| Existing primitive | Reuse | Missing capability demonstrated by the contract |
| --- | --- | --- |
| Entry and provider identity | Recorded movement, account ownership, signed amount, source identity, protected attributes | Shared import overwrites source values; one entry date cannot retain observation, posting, economic, and retrieval times or source revisions. |
| Transaction and its kind | Existing transaction editing, categories, tags, merchant, legacy presentation | One kind cannot express payroll income plus principal reduction, or a payment with principal, previously charged interest, and escrow. |
| Entry splits | User subdivisions of a recorded movement | Children inherit kind, replace the parent's contribution, and lack independent source evidence; transfer kinds cannot currently split. Splitting 120 into 90 and 30 does not establish when the 30 became expense. |
| Transfer | Relationship between account legs; matching suggestions | Matching does not prove allocation or economic meaning, and deleting a match must not create another event. |
| Valuation | Manual absolute values and existing reconciliation entry points | No named quantity, precise observation boundary, accepted evidence relation, or immutable correction history. |
| FinanceKit source records | Existing observations, lineage, revisions, conflicts, and current-record update pattern | Those capabilities are provider-specific. Reuse their records or adapters rather than making a duplicate FinanceKit history. |
| AccountStatement | Document, period, opening and closing observations | Statement dates and reconciled entries do not establish complete changes in a requested quantity. |
| Balance | Existing complete asset/investment materialization | Non-null values and flow columns, generated totals, and one account/date/currency key cannot safely represent independently missing principal and total liability. |
| RecurringOccurrence and RecurringAllocation | Schedules, partial fulfillment, currency-aware allocation, locking | Capacity is per Entry, so two legs can count twice. Removing an allocation does not retain a real reversal. |
| Budget and BudgetCategory | Expense planning and category actuals | Whole loan payments currently count as expense. Existing bill reservations are display calculations that exclude debt transfers. |

Relevant source seams include `Account::ProviderImportAdapter`,
`Financekit::Processor`, `Entry#split!`, `Transaction::Splittable`,
`Balance::Materializer`, `Balance::ChartSeriesBuilder`, `IncomeStatement`, and
`RecurringTransaction::Allocator`. The chart builder currently carries a prior
balance forward and substitutes zero before the first balance; a new calculator
alone cannot correct that reader behavior.

## Records and ownership

The names below describe a concrete logical schema. Rails models stay in
`app/models/`, with account-owned entry points and POROs where appropriate.
No new dependency or generic workflow framework is required.

### Source evidence

Add account-owned source records and immutable source revisions for providers
that do not already retain them. Existing provider-specific records may satisfy
this interface through an adapter.

- Stable identity includes source/provider, account lineage, record type, and
  provider external ID or an explicit manual/import identity. A reconnect must
  explicitly map lineage before sharing identities across connections.
- A revision records the fields needed to reproduce the financial assertion:
  original signed amount and currency, source identifiers, source-observed time,
  posting/occurrence time when supplied, pending state, inclusion basis, source
  revision or sequence, and retrieval time. Preserve absence of a field.
- Keep source amount and normalized Entry amount distinct. Retain enough of the
  source representation to explain normalization; do not rewrite raw signs to
  fit a category or infer meaning from an absolute value.
- Record a canonical payload digest and a link to any retained source payload.
  Do not require indefinite retention of every unrelated raw payload field or
  expose private payloads in ordinary read responses or public diagnostics.
- Re-fetching identical content under the same source identity is idempotent.
  Retrieval time is not part of financial revision identity. A changed payload
  creates a revision. Use authoritative source revision order when supplied;
  fetch order alone does not establish correction order.
- A documented replacement supersedes its predecessor. Concurrent or unordered
  incompatible versions remain a conflict. Retractions are retained as revisions,
  not destructive loss of the only explanation for a prior result.
- CSV/manual observations receive explicit import/declaration identities.
  Identical amount and date do not establish that two records are duplicates.

A balance observation records the asserted value, currency, boundary, and source
basis even when its quantity is unknown. Principal, total liability, and available
credit are distinct. An observation can be retained without being accepted as an
anchor for any quantity.

### Interpretation revisions and declarations

Store an append-only interpretation history with an active revision reference.
Each revision records its author or automatic rule, source/reason, affected
account and evidence references, effective dates/boundaries, financial assertions,
and the precise input fields on which those assertions depend.

Use separate fields for acceptance and current support. An accepted declaration
can later need review; an automatic proposal is not accepted simply because no
one rejected it. Suggested interpretations do not contribute finalized values.

Supported assertion types are:

- The quantity, sign convention, time boundary, and pending inclusion basis of
  a balance observation.
- Event meaning and known payment components, reporting recognition dates,
  and principal/total-liability effects, each with its own support.
- A directly valued OtherLiability account's interpretation and an explicit
  value-validity interval, including an until-known-change declaration.
- Coverage of all effects for a named quantity over exact interval boundaries.
  State whether boundaries include the endpoint events and the evidence set or
  rule that establishes completeness. A principal declaration says nothing by
  itself about interest/fee coverage for total liability.

Reusable interpretations are versioned account-scoped rules, not unrestricted
executable formulas. Use explicit predicates and supported operations such as
mapping a source field to a quantity, copying an explicitly identified amount,
or applying a declared allocation. Record conditions, dates, input dependencies,
and source precision. Rules may create proposals; only an explicitly accepted
interpretation can confer its declared meaning on matching evidence. Conflicting
matching rules require reconciliation; rule order does not silently choose truth.

An account editor can submit a declaration without an attachment. Authorization
does not make it an externally audited fact. Provider and user sources remain
distinguishable, and neither automatically wins an incompatible-value conflict.
Reconciliation records the chosen/replacement interpretation and reason while
preserving the competing evidence.

### Economic activity and components

Introduce a small durable activity identity for liability-related events, with
membership links to one or more existing Entries and their source revisions.
An activity may also arise from a statement charge or declaration without a
cash Entry. This supplies the identity required to count a two-leg payment once
and to record noncash capitalization; it is not a general posting ledger.

An accepted interpretation revision owns its component rows. Each component
contains explicit, independently nullable assertions for:

- Reporting meaning: income, expense, expense reduction, borrowing, settlement,
  escrow funding, or unresolved meaning; amount, currency, and recognition date.
- Payment funding and its allocation to principal, interest, fees, escrow, or
  unresolved remainder, when a payment is established.
- Changes in principal and total liability by account and effective boundary.
  Positive changes increase the named quantity; negative changes reduce it.
  This convention is distinct from the stored Entry movement sign.
- Links to a cost being settled, refunded, reversed, or corrected, where known.
  A supported settlement-only statement can prove no new expense even if the
  original charge is outside retained history.

Do not model these meanings as mutually exclusive event types. Payroll applied
to debt can establish income and debt reduction; an interest payment can have
funding but no new expense. Known zero is stored as zero with support. Unknown
is null with a reason, never zero.

Payment allocations must conserve the full supported payment in its currency,
including a visible unresolved remainder. They do not impose a bound on every
unknown economic or liability effect. Noncash charges, capitalization, FX, or
other evidence can describe effects beyond the payment amount. Capitalization
changes principal without creating a new cost or payment.

Membership and interpretation revisions survive Transfer deletion, source
corrections, and display splits. Keep a database constraint against duplicate
active membership of the same source movement in independent activities;
splits retain their parent activity and allocated shares. Explicit merge/split
operations revise membership and invalidate dependent results atomically.

### Supported liability results

Add a table of disposable, materialized liability results attached to Account. Leave
the existing Balance storage and asset/investment calculators intact.

Each result has account, named quantity, currency, boundary, generation,
nullable amount, support kind, reason codes, and evidence/interpretation input
references. Daily rows use an explicitly defined closing boundary; arbitrary
source observations retain their actual timestamps and can be shown separately.
Primary quantities are principal outstanding and total liability. Available
credit remains separately named borrowing capacity and does not enter net worth.
Add account credit as a separate supported quantity. A supported credit of 25
and supported debt of zero contribute +25 to net worth, displayed as “Credit 25”.
Never infer a credit solely from a negative provider sign, force it positive as
debt with `abs`, or create negative principal to accommodate it. If a source gives
only a net position and gross debt/credit cannot be established, retain its
explicit net basis; do not fabricate the missing gross components. A supported
net account position that includes every relevant component can contribute once
to net worth while its gross component displays remain unavailable. Store that
explicitly as a net account position, not as gross total liability. Do not add
both that net observation and its component values to the same aggregate.

A result is supported observed, supported reconstructed, or supported by a
validity declaration. Unavailable results distinguish unknown quantity, missing
coverage/effect/timing/FX, conflict, expired or invalidated support, and
recalculation in progress. These are reasons, not a confidence score that permits
guessing. An unavailable amount is null; supporting and conflicting observations
remain inspectable through authorized explanations.

Enforce uniqueness of account/boundary/quantity/currency within a generation and
consistency between amount and support status. A generation stores its input
revision token and calculator version. Recompute from accepted source and
interpretation revisions, not from yesterday's derived result as new evidence.

## Calculation and correction rules

### Reconstruction

For quantity Q, use an accepted anchor at boundary A and all supported changes
to Q over the exact interval from A to B. The equation is
`Q(B) = Q(A) + sum(changes to Q between A and B)`; reverse reconstruction
subtracts the same established changes. Coverage, currency, timing, and inclusion
basis must agree with the equation. A complete list of cash rows is insufficient.

Use decimal arithmetic and declared source precision. Source rounding may explain
a documented tolerance; a general matching epsilon cannot erase an unexplained
residual. When a second anchor disagrees, retain both observations and the
residual, invalidate the disputed reconstruction, and require reconciliation.
An adjustment can record a known change only with its own accepted meaning and
time; it does not establish missing interval coverage.

Principal plus separately owed interest/fees can establish total liability only
when the components are complete, nonoverlapping, in compatible currencies, and
at the same boundary. Capitalized interest is already principal. A total balance
does not establish its principal split, and principal alone does not establish
total liability.

Do not move an intraday observation to day close or fetch date. If a date-only
source has a documented or declared closing boundary, retain that interpretation
and its timezone. Otherwise preserve the ambiguous boundary. Missing ordering
blocks only results that require that order; complete daily effects may still
establish a closing result from an appropriate anchor.

A manual validity declaration supports its stated quantity only within its
declared scope. Expiry, a known change, a conflicting observation, or a source
revision invalidating its basis ends that support. A successful fetch or repeated
identical amount does not silently renew it. Freshness and historical correctness
are distinct: an old observation remains an observation at its old boundary.

### Mutation lifecycle

| Operation | Required behavior |
| --- | --- |
| First/repeat import | Retain source revision; project the movement through existing adapters; identical repeat does not add another activity, cost, funding allocation, or observation revision. |
| Changed source fields | Update unprotected display/current-entry fields as appropriate. Re-evaluate only interpretations depending on changed fields. A 120-to-125 correction invalidates its 90/30 allocation; an unrelated merchant edit does not. |
| Protected/manual Entry | Preserve the user's protected values. Retain new provider evidence separately; financial disagreement is visible and cannot be resolved by ignoring either side. Attribute locks are not proof that evidence is still valid. |
| Pending settlement | Pending activity contributes to forecasts only. A supported provider predecessor link transfers identity to the settled revision; validate changed fields before carrying interpretations. Amount/date heuristics produce candidates, not certain identity. |
| Vanished pending record | Retract a provisional authorization only with evidence that the relevant source window is complete; absence from a partial response is insufficient. No finalized expense results from a vanished authorization. |
| Source deletion/correction | Retain revision lineage and revise the original affected economic period. Do not invent a later refund. |
| Real later reversal | Create a linked later activity reversing the supported economic/payment effects. Retain the original. Reversing a payment does not reverse an independently valid earlier interest charge. |
| Match | Amount/date proximity suggests a relationship. A supported source link or explicit acceptance can join legs into one activity. Conflicting component interpretations must be reconciled before merging totals. Do not reclassify payroll or refunds by destination. |
| Unmatch | Preview impact; ask whether the entries are separate activities or their relation is uncertain. Preserve valid components, revise membership, and invalidate only conclusions depending on the old relationship. Do not duplicate a payment by deleting Transfer. |
| Split/unsplit | Keep the source parent and activity identity. Child shares conserve the movement and supported allocations. Count parent or children for the selected representation, never both. Reject or route a financially inconsistent split to review. |
| Rule edit | New revision and explicit prospective/retrospective scope. Preview affected results before applying a retrospective change. Preserve old revisions and unrelated deliberate interpretations. |
| Category/exclusion edit | Change reporting selection or category as intended, without inventing a principal allocation or removing an actual balance effect. |
| OtherLiability mode change | Explicit effective boundary and preview. Default existing accounts to their valuation interpretation; switching modes does not prove old transaction allocations or coverage. |

Writes that change evidence acceptance, activity membership, or allocations lock
the affected account/activity records in a deterministic order and use database
uniqueness constraints for source identities and active revisions. Accept the
new revision and invalidate its affected quantity/date/consumer dependencies in
one transaction. Retain author, reason, before/after revision links, and scope.
Validate that evidence, interpretations, and memberships belong to the intended
account/family and that every cross-account mutation is authorized under existing
rules. Recheck authorization and expected revision inside the mutation boundary;
a stale preview cannot overwrite a newer interpretation. Financial deletion
retains the needed source/revision tombstones without retaining a deleted entry
as an active contribution.

Background calculation takes an immutable input snapshot, builds a complete
generation, and publishes it atomically only if its input revision token remains
current. An out-of-date job cannot overwrite newer results. While affected rows
are dirty, readers expose unavailable/recalculating status rather than presenting
old rows as current support. Unaffected quantities and intervals remain usable.
Paired-account invalidation occurs in the same write transaction; aggregation
validates the input versions of contributing results so it cannot mix obsolete
and newly accepted interpretations. Failures retain evidence and record scoped
support diagnostics through `DebugLogEntry.capture(...)`.

## Reports, budgets, obligations, and readers

### Shared read contract

Provide account/domain queries for supported quantities and activity components.
All liability-aware readers use them instead of deriving meaning separately from
kind, sign, Transfer presence, or a category. Reports aggregate accepted economic
components; raw movement lists retain signed source and Entry data and their
distinct purpose. Legacy kinds remain compatibility/presentation data, not evidence.
Entries represented by the new activity components leave the legacy aggregate
path, including their asset-side counterpart entries. Other entries keep their
existing conventions. An entry must never contribute through both paths.

A quantity response contains amount or null, currency, quantity, boundary,
support status and reasons, and authorized explanation references. An aggregate
contains complete amount or null, known subtotal, completeness, and counts of
missing intended contributions within the caller's authorized scope. Reporting
responses distinguish income, expense, borrowing, payment funding, and unresolved
components. Status is quantity-specific; a payment can have known funding and
unknown principal allocation while establishing zero new expense.

Charts request an explicit date grid. Unsupported liability points remain null
and break the line. Do not carry forward or coalesce them to zero. Principal and
total liability are separate series; projections are labeled separately. Headers
can show the last supported amount and its boundary alongside current
unavailability. Household net worth uses supported values at the requested
boundary; an older displayed value is not automatically a contribution today.

Use existing account access scopes before grouping or aggregating. Explanations,
counterpart metadata, and source documents receive their own access checks.
An inaccessible counterpart contributes no disclosed name, ID, amount, or source
payload. Missing-account counts refer only to the caller's intended accessible
accounts. Shared activity identity must not expand family/account access.

### Budget and recurring behavior

Expense categories use supported economic costs and expense reductions. The debt
funding view retains full expected and paid amounts, their known components, and
the remainder due. Explain overlap with spending explicitly.

A combined planning amount is the union of identified spending-plan and
debt-funding requirements, counting their evidenced overlap once. Combine only
compatible period/currency/basis and explicitly linked components. Do not subtract
an unrelated expense total from a payment, sum prior-period costs into this
period's need, or imply that the absence of an overlap link proves no overlap.
When overlap or conversion is unknown, retain separate known figures and mark
the combined amount unavailable. Any expense-only availability label must say
that it excludes the separate debt-funding requirement.

This does not reserve cash, change Goal earmarks, or invent a cash-allocation
ledger. Existing budget arithmetic is extended only where needed to replace
whole-payment expense with supported components and present funding honestly.

Extend RecurringAllocation to refer to the stable payment activity and its
accepted funding revision. Capacity is shared across both account legs and all
occurrence allocations, with existing currency conversion and locking principles
preserved. Supported partial payment 50 against due 120 leaves 70; another leg
does not pay a second 50. Pending matches are suggestions. Real reversals retain
a linked allocation reversal and restore the affected due amount. Corrections
revise the original allocation with history. Separate paid/part-paid state from
an explicit user cancellation or waiver; a manual closed flag cannot conceal a
reversed payment. Purchase refunds do not automatically reopen debt obligations.

### Consumer checklist

| Consumer | Required change |
| --- | --- |
| Provider regular/minimal imports | Common observation/identity adapter, explicit timestamps and basis, no semantic kind override that erases accepted meaning. |
| Manual values, statements, CSV, reconciliation | Structured declarations, quantity/time/coverage controls, revision and conflict views, previews of affected results. |
| Transfer and split UI | Preserve movement/activity distinction; explicit review for invalidation and unmatch outcome. |
| Account and household charts/headers | Typed result reader, gaps, observed points, separate principal, dated last support, complete total versus known subtotal. |
| IncomeStatement, transaction search, budget | Shared economic components and completeness; refund expense reductions; no per-consumer sign/kind inference. |
| Recurring detection and fulfillment | Supported income/payment meanings, activity-level capacity, partial/reversal history, provisional pending status. |
| REST and OpenAPI | Explicit quantity, timing, reporting, funding, uncertainty, and provenance contract; maintain documented raw sign fields. Minitest behavior plus documentation-only rswag regeneration. |
| MCP/assistant | Same read definitions and authorized explanations; preserve recorded signed amount and counterpart restrictions. |
| Mobile and exports | Parse mixed/unresolved meaning and null values explicitly; no default-to-expense enum parsing, zero filling, or implicit carry-forward. |
| Insights/derived metrics | Consume completeness and avoid savings-rate/trend claims from incomplete inputs; preserve unrelated account rules. |

Deploying a new enum or null contract without its readers is not acceptance.
Document any version/capability boundary and give unsupported clients an explicit
upgrade/unsupported response for the new result contract, rather than a plausible
legacy total. Exact release order, old-client support period, and production-data
conversion belong to the migration decision. Raw movement endpoints can retain
their documented fields; they must identify them as movements rather than claim
that their legacy classification is the new economic reporting contract.

## Synthetic acceptance matrix

All amounts are independently invented, in one currency unless stated otherwise.
Support, finality, timing, and coverage are supplied explicitly by each fixture;
zeros mean supported zero. These are required outcomes, not tests reported as run.

| Case | Inputs | Independently expected result |
| --- | --- | --- |
| Separate quantities | Principal 1,000; separately owed interest 12; no other debt | Principal 1,000; total liability 1,012. Available credit does not affect either. |
| Established credit | Evidence establishes debt 0 and account credit 25 | Debt 0; account credit 25; net-worth contribution +25. Principal is zero only if independently established; no negative-principal invention. |
| Net observation only | Accepted source interpretation establishes net amount owed 80, with gross components unknown | Net-worth contribution -80 once; gross total liability, credit, and principal remain unknown. No invented decomposition. |
| Capitalization | Principal 1,000; capitalize separately owed interest 12 already recognized as cost | Principal 1,012; total 1,012; new expense 0; funding 0. |
| Principal only | Statement establishes principal 1,000; total components unknown | Principal supported; total liability unavailable, not 1,000. |
| Mixed payment | Start principal 1,000 and separately owed interest 20. Pay 120: principal 90, interest settlement 20, escrow 10 | End principal 910; total liability 910; expense at payment 0; funding 120. Debt reduction 110, not 120. |
| New interest then payment | Principal 1,000; charge interest 30; pay principal 90 plus interest 30 | Charge expense 30 once; payment funding 120; end principal and total 910. Combined overlapping plan requires 120, not 150. |
| Separate periods | Charge interest 30 in January; settle it in February | January expense 30; February expense 0 and funding 30. |
| Payroll to debt | Established wages 200 fully reduce principal; start principal/total 1,000 | Income 200; expense 0; funding/principal repayment 200; end principal/total 800. |
| Borrowing | Draw 300 into checking, both legs recorded | Borrowing 300; income/expense/funding 0; debt increases 300; cash increases 300; one event. |
| Unknown payment split | Verified payment 120; allocation and cost period unknown | Funding 120; affected expense and principal totals incomplete. Do not classify all 120 as expense or principal. |
| Known settlement | Payment 120 proven to settle earlier debt; principal split unknown | New expense 0; funding 120; principal effect unavailable. |
| Two legs | Mixed payment appears in checking and Loan, even with two old loan-payment labels | Funding 120 and supported expense once, not twice. Both movements inspectable. |
| Card purchase/payment | Purchase 100; later payment 100, with supported meaning | Expense 100 at purchase; new expense 0 at payment; payment funding 100. |
| Opening card debt | Repay 200 proven incurred before tracking | Current expense 0; funding 200. No invented purchase. |
| Refund outside history | Verified purchase refund 40; original purchase not retained | Expense -40 in receipt period; income 0; unknown category may remain unknown. |
| Duplicate correction | January purchase 100 imported twice; corrected in February | Corrected January expense 100; February expense reduction 0; retained correction lineage. |
| Real reversal | Reverse an actual payment 50 after it settled valid prior charges | Reverse funding and debt effects in reversal period; restore due 50; do not reverse the valid original charge's expense. |
| Pending settlement | Pending purchase 100, explicitly linked final purchase 105 | Final expense 0 while pending, then 105 once. No 205 total. |
| Pending disappearance | Authorization 100 disappears from a proven complete source window | Final expense 0; provisional record retained as retracted. Partial-window absence is insufficient. |
| Observed versus fetched | Monday morning observation fetched Wednesday; no interval coverage | Observation belongs to Monday morning; Wednesday current/day-close values unavailable. |
| Coverage distinction | Complete cash rows, but total-liability interest effects unknown | Cash coverage cannot establish continuous total-liability history. Principal may be supported independently. |
| Matching endpoints | Accepted opening/closing principal match listed effects, coverage unknown | Endpoints supported; intervening values remain gaps. |
| Conflicting anchors | Same quantity/currency/boundary has incompatible active observations | Preserve conflict and both observations; no arbitrary winner or silent adjustment. |
| Declared validity | Fixed OtherLiability of 500 over explicit unchanged interval | 500 supported in interval; gap after expiry or conflicting change. No automatic carry-forward. |
| OtherLiability default | Existing directly valued obligation plus unallocated transactions | Preserve valuation interpretation; no Loan arithmetic silently applied. |
| Source correction | Payment 120 allocated 90/30 becomes 125 | Preserve prior interpretation; dependent allocation/results need review. Repeating either fetch does not create another event. |
| Nonfinancial correction | Merchant display name changes; allocation depends only on unchanged financial fields | Supported allocation remains usable. If a rule depended on the name, re-evaluate that rule instead. |
| Split conservation | Split a payment without changing supported total/components | Same event, expense, funding, and debt effects; parent and children never both count. Invalid split requires review. |
| Unmatch uncertainty | User removes a match and cannot establish separate events | Preserve known components; affected combined event totals unresolved, not doubled. |
| Recurring capacity | Due 120; payment 50 with two legs; then reverse 20 | After payment due 70, not 20; after reversal due 90. |
| Missing liability/FX | Assets 2,000; one supported liability 300; another intended liability or required conversion unknown | Complete net worth unavailable; known subtotal 1,700; missing count 1 within authorized scope. |
| Partial authority | One counterpart account is inaccessible | Authorized amounts remain usable where supported; no hidden counterpart fields or expanded account totals. |
| Obsolete job | New interpretation accepted while old generation computes | Old generation cannot publish as current; affected results show recalculation until current inputs finish. |
| Cross-consumer equality | Same accounts, dates, currency, basis, and accepted revisions | Web, reports, budgets, REST, MCP, mobile, and exports agree on values and incompleteness. |

Add source fixtures for identity changes, unordered revisions, explicit zero,
negative raw signs, source retraction, missing timestamps, multiple currencies,
overlapping rules, hidden counterpart sources, and two concurrent corrections.
Assets/investments retain their existing expected behavior, including their
separate transfer conventions.

## Dependency-ordered implementation handoff

These are implementation work packages for a later effort, not new Wayfinder
decision tickets and not authorization to execute migrations now.

1. **Executable contracts and read boundaries.** Encode the matrix as independent
   Minitest fixtures and expected numbers. Define typed results and authorization
   contracts. Inventory every liability reader/writer from the research and the
   consumer checklist. Keep existing behavior available during development.
2. **Evidence and interpretation storage.** Add source identities/revisions,
   interpretation revisions, scoped declarations/rules, constraints, and conflict
   history. Adapt existing FinanceKit evidence. Establish idempotency and atomic
   invalidation tests before attaching provider writers.
3. **Activity components and lifecycle.** Add stable activity membership and
   component storage; wire import identity, pending settlement, protected fields,
   corrections, splits, and match/unmatch. Test conservation, competing writers,
   and one-event counting across account legs.
4. **Supported liability calculation.** Add the typed result storage,
   quantity/interval coverage, precise anchors, conflict/residual explanations,
   and generation publication. Prove principal-neutral effects and independent
   principal/total support. Preserve asset/investment materialization.
5. **Economic reports and funding.** Migrate liability-related reporting/search
   to components; add funding and evidenced budget overlap; extend recurring
   allocation identity and real reversal support. Preserve unrelated conventions.
6. **Correction workflows and all readers.** Add declaration/review screens and
   previews using existing DS primitives and localization. Switch charts, totals,
   API/MCP, mobile, exports, and insights together with an explicit compatibility
   boundary. Retain read-only MCP scope and existing endpoint authorization.
7. **Integrated acceptance and migration input.** Run end-to-end synthetic cases,
   current non-liability regressions, authorization checks, import/replay and
   concurrency tests. Produce before/after compatibility and data inventories
   for the production-route decision. No automatic historical truth backfill.

Independent implementation can follow these dependencies, but accepted evidence,
activity identity, and reader contracts need one integrated design. No production
cutover passes merely because the new calculator's unit tests pass.

### Validation gates for later implementation

- Focused Minitest tests at provider adapter, interpretation, calculation,
  reporting, recurring allocation, and authorized read boundaries.
- Shared expected fixture results across REST, MCP, web/model queries, mobile,
  and exports, including null handling and negative expense refunds.
- Races: duplicate import, pending/final revisions, two editors, match plus
  correction, obsolete recomputation. Assert durable invariants and visible
  outcomes rather than internal method call counts.
- Existing Loan/CreditCard/OtherLiability tests reviewed against the new contract;
  old all-principal assertions are not independent correctness evidence.
- Asset/investment, Goal earmark, family sharing, currency, and existing API
  authorization regressions remain green.
- Repository full Rails suite and required pre-PR checks; applicable system
  flows; Minitest API behavior, documentation-only rswag, regenerated OpenAPI.
- The checked private principal reference can validate the supported case under
  authorized later work. Do not claim full component history or real pending/
  reversal coverage from it. Request private artifacts only for a stated missing
  fact on which a concrete implementation depends.

## Alternatives and rejected assumptions

- **More transaction kinds alone:** cannot allocate mixed payments, distinguish
  charge from settlement, or change balance effects independently of reporting.
- **Ordinary Entry splits as accounting components:** cash subdivisions cannot
  preserve independent event/recognition timing, source revisions, and paired-leg
  identity without changing their meaning and lifecycle substantially.
- **Valuations plus a revised Loan sign formula:** do not provide quantity meaning,
  full interval effects, correct source time, or aligned reporting consumers.
- **JSON metadata as the sole financial authority:** flexible provider details
  remain useful, but identity, active revisions, conservation, conflicts, and
  typed quantity and result constraints need explicit enforced records.
- **Broaden Balance into a generic multi-quantity ledger:** its non-null cash/
  noncash flow model and existing readers would expand the change to investments
  and assets. Separate materialized liability results keep that change smaller.
- **General journal/posting architecture:** potentially useful for broader future
  accounting, but unnecessary to satisfy these cases and substantially larger.
- **Provider always wins / user always wins:** both erase genuine conflicts;
  authoritative source corrections and deliberate reconciliation are narrower.
- **Description, kind, successful sync, or endpoint equality proves an allocation:**
  none supplies the missing evidence. Explicit user interpretations remain allowed.
- **Blanket sign rewrite or principal-only repayment:** not supported by the
  accepted investigation. Preserve raw amounts and interpreted quantity separately.
- **New cash-reservation system:** the chosen budget views can express funding and
  known overlap without adding cash custody or allocation state.
- **Cached current balance and chart carry-forward:** cannot establish today's
  supported quantity or fill gaps in historical net worth.

## Remaining route decision

[Choose the production migration route and acceptance gates](https://github.com/RausserHQ/sure/issues/25)
must choose the main-based upgrade versus justified alternative, inventory
persisted production kinds/metadata and user protections, set old-client support
and rollout gates, and specify review/backfill/rollback policy. This design gives
it an explicit target; it does not preselect or execute the route.

No additional research or prototype is currently required. The unknown exact
provider component equation is representable as uncertainty. Broader products or
provider cases graduate from the map's fog only if they expose another decision
that this design cannot express.
