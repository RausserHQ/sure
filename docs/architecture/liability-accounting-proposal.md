# Independent liability accounting

Status: proposed; architecture decision in progress. No application implementation accompanies this document.

Decision: [Choose independent liability effects and balance evidence](https://github.com/RausserHQ/sure/issues/14).
Evidence: [Current-main and production map](../research/liability-accounting-evidence.md), [upstream and SimpleFIN research](../research/liability-upstream-and-simplefin.md).

## Problem established by the evidence

Current main applies every posted Loan transaction's signed Entry amount to debt. Neither the amount's sign nor a mutable reporting kind establishes which liability quantity changed. Existing valuations correct absolute values, but they cannot make an unsupported intervening path correct. SimpleFIN specifies account-relative transaction direction and a dated balance, without defining principal, total debt or interest allocation.

The proposal preserves Sure's existing Entry, Transaction, Transfer, provider ownership and reporting infrastructure. It adds independent facts for the questions that those objects cannot currently answer. The loan amortization engine remains a projection of configured terms; it is not a source of actual settled allocations.

## Proposed domain boundary

One accounting interface should answer a transaction's reporting contributions, its quantity-specific balance effects, their provenance and any unresolved conflicts. It should provide both composable SQL relations for aggregates and the corresponding serialized explanation. Controllers, MCP, recurring detection, budgets and mobile must consume this interface rather than recreate sign/kind rules.

The proposed records have the following responsibilities. Names and exact columns remain design details until the decision is accepted.

| Record or fact | Meaning | Independence |
| --- | --- | --- |
| Provider transaction evidence | Allowlisted raw amount/currency, source identity, posted/transacted times, pending state, a fingerprint and normalization version/decisions | Provider facts can refresh even when the imported Entry is protected from modification. |
| Entry | Sure's normalized account activity amount, currency and displayed date | Its sign is neither a reporting classification nor a principal effect. |
| Reporting contribution | A signed contribution to household income, expense or financing, with economic purpose and provenance | Can differ in amount and direction from Entry; a transaction may have multiple known contributions. |
| Quantity-specific balance effect | A signed change in principal, accrued interest, total liability or another explicitly supported quantity, with effective boundary, currency and provenance | Zero is a known effect. Missing or unresolved effect is not zero. |
| Transfer | A relationship between account activity, retaining its existing idempotency, rejection and counterpart semantics | Matching must never create, rewrite or delete principal assertions merely because a payment was matched. |
| Balance observation | A provider- or user-observed absolute amount with quantity interpretation, source time, time precision, pending inclusion and source provenance | A raw observation can exist while its interpretation is unresolved. An intraday reading is not automatically a daily closing anchor. |
| Accounting policy | Explicit interpretation and evidence rules selected for an account and a quantity | Product subtype alone does not prove a rule. Policies are versioned and invalidate affected derived history when changed. |

Reporting contributions and balance effects are independent child facts, not additional meanings of `Transaction.kind`. A single reporting enum plus a single principal boolean is insufficient: a combined payment may contain known expense and principal amounts; one event can change principal and accrued interest differently; a reversal can negate a prior contribution.

### Reporting contribution amounts

Positive income and expense contributions increase their respective reported metrics. A refund is a negative expense contribution with refund purpose; an income reversal is a negative income contribution. Financing identifies new borrowing or principal repayment separately from consumption. Unresolved activity contributes to an explicit unresolved bucket rather than being silently assigned an economic meaning.

A reporting contribution is not a partition of the signed Entry amount. For example, a provider's credit of 330 to a loan can represent principal reduction of 300 and household interest expense of 30. Its normalized Entry can be negative while the expense contribution is positive. A model that derives reporting direction from each component's Entry sign would reproduce the original conflation.

Where an Entry is deliberately split into ledger components, those child Entry amounts must still conserve the parent amount. Reporting contributions and balance effects must be explicitly allocated to those children; they must not be copied wholesale. Refuse a split that cannot allocate existing assertions safely, with a supported correction path. Excluding a split parent must not cause loss or duplicate application of its accounting facts.

### Quantity-specific effects

Each effective assertion names its quantity, amount, currency, effective date/time boundary and source. Increasing debt is positive; reducing debt is negative. Known principal-neutral activity has an explicit principal effect of zero. An effect's amount need not equal Entry.amount. Effects on different quantities must not be summed together.

A transaction may have principal +100 and accrued interest -100 when interest is capitalized, with total liability unchanged. It may have principal zero and accrued interest +30 when interest accrues. It may have principal -300 and total liability -330 when a combined payment settles principal and interest. These examples require independent evidence; they are not automatic default interpretations of a description.

For each requested quantity, the accounting interface returns a known effect or unresolved status. The absence of a row cannot imply neutrality. Pending transactions do not enter booked history; pending-inclusive observations remain a distinct kind of evidence.

### Provider evidence and normalization

Keep a bounded provider-owned namespace for transaction facts using the existing metadata ownership/replace mechanism. Retain raw numerical amount and currency, provider dates, pending flag, safe source identity, selected structured codes where needed, normalization version, and specific decisions. Do not duplicate credentials, full `extra` objects, descriptions, payees or raw payloads into the diagnostic contract.

Provider corrections replace the owned facts rather than deep-merging withdrawn values. Store a fingerprint of the allowlisted facts. Exact repeats are no-ops. For a changed fingerprint, recompute only provider-derived assertions under the recorded policy. Preserve user assertions and expose disagreement. Refresh source evidence before protected-Entry early returns so operators can distinguish a stale protected Entry from the provider's corrected state.

The boundary may use documented structured provider fields and explicit account interpretation. SimpleFIN alone does not authorize a principal effect or balance quantity. Institution recognition, if supported by independent evidence, belongs in an ingestion policy with a version and synthetic tests; it cannot leak into reports or balance calculators. Description matches may suggest a review, but are not sufficient evidence for principal arithmetic.

## Balance observations and reconstruction

Store observations in the application database with lineage to the existing account/provider. Distinguish the raw reported quantity and amount from an accepted interpretation. Preserve source timestamps; do not replace them with the sync date. Record source field (`balance` versus `available-balance`), currency, pending inclusion and precision. A fallback to available credit must not silently become a debt anchor.

An account can have evidence for more than one quantity. Define which quantity its primary account-history series displays, and label it. Principal and total liability are never silently substituted. Additional quantities remain independently queryable; a declared composition may combine them only when all components are complete and non-overlapping.

Retain existing valuations as explicit absolute observations/resets with their provenance. A legacy valuation without a known quantity is not automatically principal. A user-entered correction may serve as an authoritative reset after the user identifies its quantity and boundary. Preserve any discrepancy as an explained residual; never invent a transaction to make the numbers agree.

### Conditions for a reconstructed segment

A segment requires:

1. An accepted anchor for exactly the same quantity and currency.
2. An established anchor boundary. SimpleFIN's timestamp is a point observation, not proof of day close.
3. Known effects, including known zeros, for all relevant activity in the interval.
4. Evidence or an explicit user assertion that the interval's activity coverage is complete. A successful API request or absence of imported rows does not establish completeness.
5. Known effective ordering/boundaries and required FX rates. A missing conversion is a gap, not a skipped zero.

Within such a segment, forward balance equals anchor plus subsequent signed effects; reverse balance subtracts the same effects. An observation/effect exactly on the boundary is applied once, according to an explicit inclusivity convention. With two accepted anchors, compare their difference with the interval's effects. A nonzero residual invalidates the claim of a fully explained segment and is returned in the explanation.

For date-only effects, reconstruction uses an explicitly selected day boundary. It cannot cross an intraday anchor when the effect's ordering relative to that anchor is unknown. Dated closing observations can support daily reconstruction; raw intraday observations can still be shown as observed points with their timestamps.

### Unknown history and aggregation

The user selected **observed points with gaps** for uncertain liability history. There is no automatic legacy-estimate fallback. Remove or invalidate legacy derived liability rows when their assumptions no longer hold, while retaining observations, valuations and source evidence. Unknown is not a zero balance and not yesterday's balance.

A series point must describe its quantity, value when known, observation/reconstruction status and evidence references. Chart generation must stop unconditional carry-forward and `COALESCE`-to-zero for uncertain series. Net-worth aggregation must track missing constituents, including unavailable FX. The user selected **a gap for the complete total plus a separately labeled known subtotal and missing-account count** on 2026-09-26.

The account's selected valuation basis also needs to remain visible when aggregating liabilities. A principal observation must not be labeled as a measured total-liability observation. Selection of a valuation basis is explicit policy, separate from claiming principal equals total debt.

## Transfer lifecycle and reporting ownership

Preserve base reporting contributions and balance effects when matching, unmatching, rejecting, importing again, or changing either leg. Route all automatic/manual/rule/creator entry points through one relationship operation; preserve existing idempotency and concurrency protections.

For ordinary sign-derived classifications, matching may project a transfer classification without rewriting the base assertion. Explicitly established payroll income, expense or financing survives that projection. `kind` may remain a compatibility/display field during transition, but no calculator or aggregate may depend on its mutable transfer value.

A relationship alone is not proof that two explicitly reported economic contributions are distinct events. When one leg supplies explicit economic evidence and the other only has a sign-based inference, count the explicit contribution once. When both legs assert the same economic event, require or retain an explicit reporting owner/deduplication decision. Conflicting or ambiguous dual assertions must be surfaced as unresolved rather than silently counted twice or discarded. This decision concerns reporting ownership and has no effect on either leg's balance effects.

Known transfer fees remain separate ordinary component transactions, as upstream already models them. Interest may use the same component precedent when known and not already represented by another provider event. An amortization estimate does not justify creating an additional expense.

## Imports, corrections and ownership

| Transition | Required rule |
| --- | --- |
| Exact repeat import | Stable identities, evidence fingerprints and normalization versions yield unchanged facts and derived results. |
| Provider corrects amount/date/pending | Refresh provider facts; replace provider-owned derived assertions; invalidate the earliest affected history boundary and reporting caches. |
| User-modified/import-locked/excluded Entry | Retain protected fields and user accounting assertions; refresh safe provider evidence and expose disagreements. Exclusion from reporting does not imply a zero balance effect. |
| Pending becomes posted | Retain identity correlation and raw provider dates; apply effects once on the established effective boundary. Recompute when a changed amount is confidently linked; leave uncertain identity matches unresolved. |
| Match/unmatch/reject | Change relationship and reporting projection/ownership only. Independent balance facts survive. |
| Split/unsplit | Conserve ledger amount and deliberately allocate all existing facts. Prevent duplicate parent/child application. |
| Provider removes/reverses activity | Require source-supported reversal/removal semantics; absence from a rolling feed is not deletion. Preserve lineage and invalidate only the justified interval. |
| Policy changes | Version the new interpretation, retain source evidence, invalidate affected derived values, preserve user assertions and expose conflicts. |

Source facts, user assertions and effective projections must be distinguishable. A last-write-wins update across these owners is not a reconciliation policy.

## Migration approach

Add schema before switching readers, then route semantics through the central interface and remove old independent kind/sign decisions. Prefer database constraints for identity, allowed quantities, provenance and currency consistency. Exact schema and rollout migration details follow the accepted decision.

Deterministic migrations may preserve current non-liability behavior as explicitly identified legacy inference, carry direct user assertions where their actual ownership is known, retain Transfer relationships, and retain absolute valuation evidence with its original limits. A broad `user_modified` flag does not prove that the user reviewed principal or reporting meaning.

Existing `loan_payment` does not establish the principal/interest split and may even represent misclassified payroll. Neither it nor `loan_proceeds`, `cc_payment`, `funds_movement`, `refund`, `unclassified` or `standard` alone proves an independent principal effect. The production-only kinds require a compatibility migration if that branch is ever advanced; they must not be assumed to exist in current main.

The user selected **unresolved activity excluded from household income/expense totals** on 2026-09-26. Migration preserves the prior kind for audit and exposes unresolved amounts/counts. It does not retain legacy classifications as silently verified reporting. Balance history independently follows the selected gaps policy.

Resync supplies facts that the provider can actually establish. It cannot manufacture missing principal semantics or historical coverage. The user selected **explicit accounting controls in the source release** on 2026-09-26. A supported application workflow must let an authorized user identify an account's balance quantity/sign/boundary and assert known event effects or component amounts, with provenance, validation and resync protection. This is required for a useful generic model when SimpleFIN is silent; a database-only correction path is insufficient.

Protected rows are reconciled only where a conflict is deterministic. No broad description-driven migration or repair script, no recurring repair process, and no production mutation are part of this source work.

## Reporting, API and operator contract

All consumers use the same effective reporting relation and independent balance evidence. Household income/expense exclude financing and principal repayments. Refunds reduce expenses, including when refunds exceed purchases in a period; a negative net expense must not be relabeled as new household income. Budgets use consumption expense; a separately labeled principal-outflow metric may be added without changing expense semantics. Recurring detection uses confirmed/inferred reporting purpose and preserves its existing declared-obligation concept.

The SQL boundary must explicitly change aggregation grain. First select unique eligible Entry IDs using existing family/account access, date, pending, exclusion and split-parent constraints. Then emit one row per effective reporting contribution, with its own signed amount and one resolved category. IncomeStatement totals, daily expenses, category statistics and family statistics consume that relation. Joining multiple contributions into the existing `at`/`ae` scope and continuing to sum Entry amounts would multiply values. Activity counts use distinct Entry IDs; contribution counts, if useful, are separate.

Search and recurring detection remain at one row per Entry. Reporting-purpose filters use `EXISTS` or a distinct Entry-ID subquery. Search must distinguish reporting totals from normalized activity totals rather than change the meaning of amount filters silently. Recurring amount clustering and allocation capacity still use the original Entry amount; a composite event cannot be duplicated into multiple recurring candidates merely because it has several reporting contributions.

REST and MCP retain existing normalized signed amounts and add structured reporting, relationship and balance-effect fields. Monetary precision and currency must remain explicit; presentation-signed cents are not renamed raw provider amounts. Mobile must retain financing/refund/transfer/unresolved/mixed states and known/unknown balance status, instead of mapping every non-income value to expense or every missing balance to zero. API documentation and compatibility notes must describe intentional behavior changes.

Read-only diagnostics are family/account scoped, with existing API scopes and counterpart access restrictions. They expose only allowlisted evidence: source and correlation identity, raw and normalized amounts/dates, reporting contributions, relation/ownership, quantity effects, pending/protection/conflicts, observation interpretations, policy/version and normalization decisions. Do not serialize arbitrary provider metadata.

A balance explanation returns the selected quantity, anchor(s), applicable effects, coverage/boundary assumptions, explicit residual and certainty. Unknown results explain the missing evidence. Pagination and date bounds prevent payload dumps; existing `DebugLogEntry` captures support-relevant normalization failures without secrets.

## Alternatives considered

| Alternative | Assessment |
| --- | --- |
| Add kinds and fix stored signs | Cannot express independent reporting/effects or partial amounts; matching can still destroy meaning. Rejected. |
| Extend existing split/fee transactions alone | Useful for known ledger components, but does not represent neutral or unknown principal effects, multiple liability quantities, or snapshot authority. Retain as a component primitive, not the entire model. |
| One principal-effect enum/boolean | Cannot describe partial amounts, simultaneous quantity changes, provenance or missing evidence adequately. Rejected. |
| Infer actual effects from amortization | Confuses scheduled payments with provider activity and fails revolving, variable/extra payments and capitalization. Rejected as authoritative evidence. |
| Rebuild Sure as a general double-entry accounting engine | May represent the domain, but replaces unrelated asset/investment/provider behavior and is not necessary to satisfy the demonstrated gap. Defer. |
| Independent reporting contributions, quantity effects and typed observations within Sure | Proposed. Keeps Entry and Transfer identities, extends evidence and makes uncertainty explicit at the shared query/calculation boundary. |

## Synthetic acceptance matrix

Use only synthetic data and verify behavior at the shared query, calculator, lifecycle and external contract boundaries.

| Scenario | Decisive expected result |
| --- | --- |
| Principal advance 1,000 | Financing; principal +1,000; household income/expense zero. |
| Principal repayment 300 | Principal -300; consumption expense zero; distinguishable from interest. |
| Payroll 500, principal-neutral evidence | Income +500; principal zero even if matched. |
| Interest 30, principal-neutral evidence | Expense +30; principal zero; optional accrued-interest effect independent. |
| Card payment 200, principal-neutral evidence | Payment/transfer relationship; principal zero before and after match/reject/resync. |
| Mixed five-event day from evidence map | Principal 10,000 → 10,700, regardless of Entry net 430. |
| Different documented policy | Payroll can reduce principal; capitalized interest can increase principal. No universal zero shortcut. |
| Combined payment 330 | Expense 30 and principal -300 when explicitly established; no inferred split if unknown. |
| Refund exceeding period purchases | Negative net expense remains an expense credit; no household-income inflation. |
| Reversal | Negates the correct prior contributions/effects, with provenance. |
| Lifecycle and repeat imports | Independent assertions survive automatic/manual/rule matches, creation, rejection, unmatch and repeated import. |
| Correction and pending settlement | Converges on corrected facts exactly once; protected disagreement visible. |
| Splits | Ledger conservation and explicit effect allocation; no parent/child double count. |
| Dated anchors | Forward and reverse paths agree; same-boundary effects applied once; unexplained residual visible. |
| Missing semantics, coverage, FX or ordering | Observed points and gaps; no fabricated daily values or aggregate zeros. |
| Authorization | No cross-family/account raw evidence or inaccessible counterpart leakage. |
| Existing behavior | Asset/investment flows, known fees, manual records, exclusions/protection, projections and API precision preserved or intentionally migrated. |

## Production compatibility

The proposed model could be ported to v0.7.4 as a coordinated domain/schema/reporting change; it is not a safe small cherry-pick. Current main has shared reporting queries, newer transfer/pending protections and loan projection/rate primitives absent from that branch. Implementing and maintaining two versions would multiply the most sensitive migration and accounting paths.

Prefer moving production to a reviewed newer base after source validation, then applying this model through normal deployment. Current-main projections are not themselves the liability fix and do not require the new evidence model to imitate their architecture. Independent observability fixes may remain reasonable backports, but an accounting backport should be chosen only if an external deployment constraint justifies its duplicated verification burden.

The source work must ship deterministic migration/conflict diagnostics. It cannot promise that normal SimpleFIN resync will resolve household rows whose semantics are absent from the protocol. The later production acceptance step should reconcile only explicitly supported interpretations and protected conflicts against private evidence. If that evidence still cannot identify an effect or boundary, the correct result remains unresolved rather than a guessed repair.

## Remaining decision frontier

- The uncertainty policies are settled: observed account points with gaps; incomplete aggregate totals shown as gaps with a known subtotal; unresolved reporting excluded from household income/expense totals and visible for review.
- The supported interpretation workflow is settled: include explicit accounting controls with provenance and resync protection. Finalize the proposed independent contribution/effect/observation boundary against its persistence and query interfaces.
- Specify exact schema, evidence precedence, reporting ownership and coverage assertions; these are part of this architecture decision, before implementation tickets are created.
- After acceptance, record an ADR and a minimal dependency graph with migration, core domain, ingestion/lifecycle, consumers/diagnostics and regression/review gates. Do not treat this proposal as implemented behavior.

## Example read contract

This synthetic example describes the proposed information boundary, not an implemented endpoint or a claimed SimpleFIN payload. Monetary values are decimal strings; the raw provider sign is intentionally absent because this example supplies no raw provider evidence.

```json
{
  "normalized_entry": { "amount": "-330.0000", "currency": "USD" },
  "reporting": {
    "status": "complete",
    "contributions": [
      { "metric": "expense", "purpose": "interest", "amount": "30.0000", "currency": "USD" },
      { "metric": "financing", "purpose": "principal_repayment", "amount": "-300.0000", "currency": "USD" }
    ]
  },
  "balance_effects": [
    { "quantity": "principal", "status": "known", "delta": "-300.0000", "currency": "USD" },
    { "quantity": "total_liability", "status": "unresolved", "delta": null, "currency": "USD" }
  ],
  "relationship": { "matched": true },
  "evidence": { "origin": "user_assertion", "provider_conflict": false }
}
```

The explicit total-liability uncertainty is intentional: knowledge of principal and an expense contribution alone does not establish when interest was recognized in the provider's outstanding balance.
