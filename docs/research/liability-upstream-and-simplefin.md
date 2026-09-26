# Upstream and SimpleFIN evidence for liability accounting

**Scope.** External, primary-source evidence only. Verified against `we-promise/sure` through 2026-09-26; the supplied local base is `437c317606497d713a6683f8d8c9a64a17602efd`.

## Conclusion

The SimpleFIN protocol supplies a signed account-relative transaction amount and a dated account balance, but no liability taxonomy, loan-principal meaning, balance-sign convention for liabilities, interest breakdown, or institution-wide semantic guarantee. An imported liability balance must therefore be retained as a provider observation with provenance; classifying it as debt, credit, principal, or expense is application policy or user/institution evidence.

The upstream already has the relevant operational primitives in the fixed base: explicit SimpleFIN credit-card sign overrides, Loan-specific normalization, dated reconciliation/boundary-adjustment balance machinery, transfer fee component transactions, and loan amortization projections. They solve narrow symptoms, but none establishes a generic principal/interest decomposition for imported activity. The strongest existing upstream design thread to extend is [Should mortgage payments count as expenses in the income statement? (Discussion #2620)](https://github.com/we-promise/sure/discussions/2620): retain its distinction between balance-sheet repayment and expense, and reuse the component-transaction precedent in [Add Bank Charges for Transfers (PR #2183)](https://github.com/we-promise/sure/pull/2183) only where component amounts are known or deliberately entered.

## Protocol facts (observed)

The current [SimpleFIN Protocol v2 draft](https://www.simplefin.org/protocol.html) says:

* An account has required numeric-string `balance` and required `balance-date`; `available-balance` is optional and can be omitted when equal to balance. It does not say whether either is asset value, available credit, payoff amount, or principal. [`Account`](https://www.simplefin.org/protocol.html#account)
* A transaction amount is a numeric string and **positive means deposited into the account**. That is account-relative direction, so it cannot itself state whether a liability payment is income, spending, or principal reduction. [`Transaction`](https://www.simplefin.org/protocol.html#transaction)
* `pending` is optional, defaulting to false when absent; `posted` may be zero while pending. `/accounts` excludes pending data by default, and `pending=1` requests it only if the server supports it. [`Transaction`](https://www.simplefin.org/protocol.html#transaction), [`GET /accounts`](https://www.simplefin.org/protocol.html#get-accounts)
* Account and transaction `extra` objects are optional and server-defined. IDs are only unique within their enclosing connection/account. A connection’s organization ID is only unique per SimpleFIN server. [`Account`](https://www.simplefin.org/protocol.html#account), [`Transaction`](https://www.simplefin.org/protocol.html#transaction), [`Connection`](https://www.simplefin.org/protocol.html#connection)
* The spec remains draft; servers may report v1/v2 without implementing every draft feature. It supports custom currencies as well as ISO currencies. [`GET /info`](https://www.simplefin.org/protocol.html#get-info), [`Custom Currencies`](https://www.simplefin.org/protocol.html#custom-currencies)

**Inference.** Feed behavior described in upstream issues (for example, a bank reporting a positive loan amount or an ambiguous credit-card sign) is institution behavior. It is not safe to encode as a SimpleFIN-wide protocol rule.

## v1 compatibility versus v2 draft

[v1.0.7](https://www.simplefin.org/protocol-v1.html) is the stable compatibility document; [v2.0.0](https://www.simplefin.org/protocol.html) labels itself a draft. Both require top-level `accounts`, and per account require `id`, `name`, `currency`, `balance`, and `balance-date`; both make `available-balance`, `transactions`, `extra`, `transacted_at`, and `pending` optional. Both specify that positive transaction amount means a deposit into that account, and exclude pending by default unless `pending=1` is requested (if supported). The protocol inference boundary in this report therefore applies to both versions.

| Version | Topology and required response fields | Consequence |
|---|---|---|
| [v1.0.7](https://www.simplefin.org/protocol-v1.html) | An account has required nested `org`; Account Set requires `errors` and `accounts`. `org` requires `sfin-url` and either `domain` or `name`. | A top-level-account importer is operating on the v1 shape. It must not require optional transactions/extensions. |
| [v2 draft](https://www.simplefin.org/protocol.html) | Nested `org` is deprecated for required top-level `connections`; accounts require `conn_id`; `errlist` replaces deprecated `errors`; `balances-only=1` and `version=2` are new. | Do not assume v2 topology or balances-only exists on a v1 server. `/info` itself cautions that servers may report 1 or 2 without every draft feature. |

The site offers no deployed-provider adoption census. Only a particular endpoint’s `/info` response and actual payload establish its negotiated shape; neither contract supplies a liability-account semantic guarantee.

## Upstream history and status at the fixed base

All commits below are ancestors of `437c317`; they are already present on the **current-main design base**. Production ancestry is recorded separately.

| Evidence | What the merged diff actually establishes | Limit |
|---|---|---|
| [Chase debt accounts synced with SimpleFIN show negative balances (Issue #406)](https://github.com/we-promise/sure/issues/406) → [Simplefin liabilities recording fix (PR #410)](https://github.com/we-promise/sure/pull/410) | Initial SimpleFIN normalization made provider-negative CreditCard/Loan balances positive; it also changed first-sync history behavior. | The issue discussion records conflicting provider observations; it did not establish a universal sign rule. |
| [Add overpayment detection for SimpleFIN liabilities (PR #412)](https://github.com/we-promise/sure/pull/412), tightened by [Fix SimpleFIN liability balance sign when transaction history is incomplete (PR #642)](https://github.com/we-promise/sure/pull/642) | Added `SimplefinAccount::Liabilities::OverpaymentAnalyzer`, using a finite transaction window/raw payload fallback; the later fix falls back when transaction net and observed balance differ materially, including incomplete/pending history. | It is a heuristic, explicitly vulnerable to missing/sparse or atypical provider activity. |
| [Respect manually selected account type in SimpleFIN liability logic (PR #1214)](https://github.com/we-promise/sure/pull/1214) and [Amex savings account synced with SimpleFIN shows negative balance (Issue #1226)](https://github.com/we-promise/sure/issues/1226) | An explicitly linked account type outranks mapper-derived liability classification, preventing a provider mapping from forcing an asset negative. | Account type is still application classification, not provider proof of amount meaning. |
| [Fix SimpleFIN inverting Loan account balances (PR #1574)](https://github.com/we-promise/sure/pull/1574) | `SimplefinAccount::Processor#process_account!` bypasses the analyzer for `Loan` and stores `observed.abs`; test pins a positive imported mortgage balance. | Its PR rationale treats positive outstanding principal as a bank convention. That conclusion conflicts with the earlier negative-liability generalization and is not backed by SimpleFIN’s contract. |
| [SimpleFIN: add a credit card balance sign override (PR #3243)](https://github.com/we-promise/sure/pull/3243) | Adds persisted `SimplefinAccount#balance_sign_override` (`credit`/`debt`) for CreditCard, checked before the heuristic in regular and minimal imports; UI change queues sync. | A narrowly scoped manual resolution for ambiguous sign; it does not cover Loan or semantic component allocation. |
| [Reverse balance sync injects an unexplained opening-anchor plug (Issue #2497)](https://github.com/we-promise/sure/issues/2497) → [Fix reverse balance opening boundary adjustments (PR #2502)](https://github.com/we-promise/sure/pull/2502) | Reverse calculation explicitly persists the difference at `opening_anchor_date + 1` as cash/non-cash adjustments, including liability flow direction. Its tests cover calculator and materialized rows. | It makes an existing unexplained reconstruction difference auditable; it cannot determine why provider facts and imported activity diverge. |
| [Add variable interest rate loan amortization and tracking (Issue #3295)](https://github.com/we-promise/sure/issues/3295) → [Amortisation engine and variable-rate loans (PR #3473)](https://github.com/we-promise/sure/pull/3473) | Adds loan variable-rate schedule/projection primitives, effective-rate history, date/term validation and UI. The migration is additive. | The schedule is a projection from configured terms/rates, not evidence that a provider transaction’s lump sum contains a particular principal/interest split. |
| [Add Bank Charges for Transfers (PR #2183)](https://github.com/we-promise/sure/pull/2183) | Transfer fees are represented as related ordinary `Transaction(kind: "standard")` component rows; the principal transfer stays `funds_movement`. Its tests assert components and updated derived fee amounts. | It models known fee components; it is not a basis to infer unknown mortgage interest automatically. |

## Exact merge and production lineage

The source table above describes semantics. This table records the exact SHA test requested by the parent: all named merges are ancestors of fixed main `437c317`. `production ✓` means that exact upstream merge SHA is an ancestor of `aab841b`, so it cannot be misreported as missing due to a cherry-pick.

| PR | Merge SHA | Fixed main | production/v0.7.4 | Evidence note |
|---|---|---:|---:|---|
| [Simplefin liabilities recording fix (PR #410)](https://github.com/we-promise/sure/pull/410) | `a91a4397e923992414e01dad024edea0100b46d0` | ✓ | ✓ | Original SimpleFIN liability sign normalization. |
| [Add overpayment detection for SimpleFIN liabilities (PR #412)](https://github.com/we-promise/sure/pull/412) | `78aa064bb02eaf64235d134e2211ef100c3cefa0` | ✓ | ✓ | Analyzer. |
| [Fix SimpleFIN liability balance sign when transaction history is incomplete (PR #642)](https://github.com/we-promise/sure/pull/642) | `a780b3442178e41c91fc6963cb693a395e9b0e23` | ✓ | ✓ | Incomplete-history safeguard. |
| [Respect manually selected account type in SimpleFIN liability logic (PR #1214)](https://github.com/we-promise/sure/pull/1214) | `26aa260fb1a44c845aab98221956582a4c12da83` | ✓ | ✓ | Manual account type precedence. |
| [Fix SimpleFIN inverting Loan account balances (PR #1574)](https://github.com/we-promise/sure/pull/1574) | `7c14c80444c34e16221ab60c7b49cf3735ef788b` | ✓ | ✓ | Loan sign bypass. |
| [Preserve historical balances as waypoints for linked accounts (PR #1663)](https://github.com/we-promise/sure/pull/1663) | `ba3b20627d6d00ba8c139d78e97770e56f2f892a` | ✓ | ✓ | Current-anchor rotation into reconciliation waypoints. |
| [Derive waypoint start from day’s flows (PR #2031)](https://github.com/we-promise/sure/pull/2031) | `2620653b2abeb090f0cb5d7f6e0075dfbe453d65` | ✓ | ✓ | Waypoint same-day flow correction. |
| [Add Bank Charges for Transfers (PR #2183)](https://github.com/we-promise/sure/pull/2183) | `edb91cad6fd227b4045f5d21014237bacc99fd9e` | ✓ | ✓ | Known transfer fee components. |
| [Fix reverse balance opening boundary adjustments (PR #2502)](https://github.com/we-promise/sure/pull/2502) | `59c47c4c665522611e89aa244e322d698b012798` | ✓ | ✓ | Explicit opening-boundary adjustment. |
| [Add native amortization schedules for loan accounts (PR #2984)](https://github.com/we-promise/sure/pull/2984) | `6c1c8eeec547204fb5a4e1e75d2114c6796a23e6` | ✓ | ✗ | Fixed amortization schedule. Production lacks the schedule file, so no whole-PR equivalent is present. |
| [SimpleFIN: add a credit card balance sign override (PR #3243)](https://github.com/we-promise/sure/pull/3243) | `01361205605578fc4973119fa07909120f599705` | ✓ | ✗ | Credit-card sign override. Production lacks its additive migration. |
| [Amortisation engine and variable-rate loans (PR #3473)](https://github.com/we-promise/sure/pull/3473) | `117dd80c128d7dab3987013d19d22ca6a3f6f9d8` | ✓ | ✗ | Variable-rate extension; production lacks prerequisite schedule delivery and the variable-rate migration. |

Two linked PRs are not merged and therefore are not current-main or production evidence: [Zero flows on reconciliation waypoints in ReverseCalculator (PR #2009)](https://github.com/we-promise/sure/pull/2009) closed unmerged, and [Stop freezing mid-day provider readings as waypoints (PR #3519)](https://github.com/we-promise/sure/pull/3519) remains open. Neither supports a claim that its proposed anchor behavior exists in the fixed base.

## Later and linked history

* [Add native amortization schedules for loan accounts (PR #2984)](https://github.com/we-promise/sure/pull/2984), the original fixed-rate amortization delivery, expressly excludes automatic splitting of synced mortgage payments: the imported payment is transfer-matched, and transfers were not splittable. It names unmatch → split → re-match as separate transfer-system work. Its `payment_for(date)` is a projection primitive, not source evidence for an imported amount.
* [Persist daily balance snapshots for linked accounts (Issue #1492)](https://github.com/we-promise/sure/issues/1492) was delivered by [Preserve historical balances as waypoints for linked accounts (PR #1663)](https://github.com/we-promise/sure/pull/1663); [Derive waypoint start from day’s flows (PR #2031)](https://github.com/we-promise/sure/pull/2031) fixed same-day transaction double count. The still-open [Stop freezing mid-day provider readings as waypoints (PR #3519)](https://github.com/we-promise/sure/pull/3519) identifies an unresolved timing question: a sync-time provider reading is not necessarily the day-close value before it becomes a reconciliation waypoint.
* [SimpleFIN transfers to pay loan accounts get incorrect `loan_payment` kind (Issue #3063)](https://github.com/we-promise/sure/issues/3063) remains open: a SimpleFIN transfer to a Loan can give both legs `loan_payment`, double counting reporting. [OtherLiability payment transfer does not reduce liability balance (Issue #1192)](https://github.com/we-promise/sure/issues/1192) remains open: an OtherLiability payment transfer may not reduce the balance. These are direct evidence that transfer kind and balance effects are not yet coherent across liability types.
* [Reporting relies on transaction `kind`, not persisted Transfer (Issue #2860)](https://github.com/we-promise/sure/issues/2860) remains open: reporting uses mutable transaction `kind` while a persisted `Transfer` also exists, leaving two authorities after a preceding reporting fix. This strengthens the case for selecting one authority before changing loan repayment reporting.
* Open balance-history/reconciliation risks materially related to provider observations: [Enable Banking reverse sync shifts history when current balance includes pending (Issue #3540)](https://github.com/we-promise/sure/issues/3540), [Valuations do not update linked-account displayed balance (Issue #3385)](https://github.com/we-promise/sure/issues/3385), [Two concurrent balance updates can create duplicate valuations (Issue #3339)](https://github.com/we-promise/sure/issues/3339), and [SureImport fabricates opening anchors from current balance (Issue #3360)](https://github.com/we-promise/sure/issues/3360). These reports remain open and are claims/reproductions, not merged specification.

## Search coverage

The following authenticated GitHub primary-source searches were run verbatim with `gh search issues --repo we-promise/sure --limit 100`: `SimpleFIN`; `loan transfer`; `balance history`; `loan repayment`; `loan refund`; `transfer lifecycle`; `current_anchor`; `reconciliation`; `mortgage interest`; and `transfer match`. Direct timeline inspection was run for the linked-balance snapshots, reverse-boundary adjustment, and variable-rate loan issues. Direct PR metadata/files/diffs were read for the titled PRs in the lineage table.

Significant unresolved results are [SimpleFIN loan-transfer kind double count (Issue #3063)](https://github.com/we-promise/sure/issues/3063), [OtherLiability payment does not reduce balance (Issue #1192)](https://github.com/we-promise/sure/issues/1192), [two transfer-reporting authorities (Issue #2860)](https://github.com/we-promise/sure/issues/2860), [Loan Starting Point (Issue #3383)](https://github.com/we-promise/sure/issues/3383), and the four linked balance-history reports above. No result for the exact `loan refund` or `transfer lifecycle` queries was returned. This is search coverage, not proof that no differently worded report exists.

## Reporting direction (proposal, not merged decision)

[Should mortgage payments count as expenses in the income statement? (Discussion #2620)](https://github.com/we-promise/sure/discussions/2620) remains open. Its opening argument and maintainer response identify the present `loan_payment` reporting rule as intentional but coarse: a mortgage principal payment is balance-sheet movement, and separately imported interest can be double-counted. The discussion proposes either mortgage-specific funds movement or an account-level “treat repayments as spending” setting. Later discussion points to the titled transfer-fee component approach above for known interest/escrow components. None is a merged architecture decision.

## Risks and unknowns requiring verification

* Confirm the local provider adapters preserve raw SimpleFIN `balance`, `available-balance`, `balance-date`, `pending`, and `extra` values distinctly enough to label downstream interpretation as derived.
* Confirm current `Loan` normalization and the credit-card override have the same behavior in both normal and balances-only imports; the sign-override PR covers both, but local regressions could differ.
* Establish which dated balance observation is authoritative when a server emits unavailable/available/current values or incomplete transactions. The protocol does not choose.
* Do not infer interest, escrow, fees, or principal from description text or an amortization schedule without an explicit user/provider source and uncertainty policy.

## Recommended next action

Treat the titled mortgage-payment discussion above as the upstream policy thread. Extend existing components rather than introduce a schema from protocol speculation: preserve provider observations first; use `balance_sign_override` only as manual sign policy; keep the titled reverse-boundary adjustments explicit; and create linked standard component transactions only for known/user-supplied interest or fee amounts. Verify the local call paths before deciding whether a general account-level reporting policy belongs on the account, transfer relationship, or reporting layer.
