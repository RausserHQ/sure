# What liability evidence can prove

Research for [Establish what liability evidence can prove](https://github.com/RausserHQ/sure/issues/20), under [Wayfinder: plan end-to-end liability correctness from main](https://github.com/RausserHQ/sure/issues/19).
Reviewed 2026-09-26; planning baseline `437c317606497d713a6683f8d8c9a64a17602efd`.

## Finding and scope

SimpleFIN describes account observations and money direction. It does not establish a principal ledger or explain every change in a liability balance. Independent examples need a named balance quantity, its time boundary, and evidence allocating the relevant events.

This report resolves the research question by separating documented guarantees from unknowns. It does **not** establish that the motivating account has been reconciled. No application behavior was validated, and no household result was independently reproduced here.

This is new planning research. Earlier research was used to locate sources; its architectural and operational recommendations carry no authority into this report. No data model, reporting rule, gaps policy, migration route, or authorization for production work is selected.

## Evidence classes

| Class | Meaning in this report |
| --- | --- |
| Protocol requirement | What the published SimpleFIN document says a conforming implementation supplies. It is not proof that a particular institution implements it faithfully. |
| Service documentation | SimpleFIN Bridge's published behavior and limits, distinct from the protocol. |
| Institution documentation | Generic public product terms, not the motivating account's executed agreement or feed mapping. |
| Reported diagnostic | An attributed conclusion recorded in the existing private investigation. |
| Independent verification here | Reading the cited primary documents and recorded issue comments. No raw provider payloads, importer execution, or financial reconstruction. |
| Analytical example | A synthetic case with explicitly assumed components, used to identify necessary evidence. |

## Published protocol and service limits

The following compact summary covers the relevant contract; citations identify the source for each row.

| Source | Documented fact |
| --- | --- |
| [v1 Account](https://www.simplefin.org/protocol-v1.html#account) | Required `balance` and `balance-date`; optional `available-balance`; optional transaction subset. The timestamp describes when the balances became their values. |
| [v1 Transaction](https://www.simplefin.org/protocol-v1.html#transaction) | Positive amounts mean deposits. `posted` marks posting; optional `transacted_at` marks occurrence. Pending may have `posted=0`; absent `pending` means posted. IDs cannot be reused within an account. |
| [v1 request bounds](https://www.simplefin.org/protocol-v1.html#get-accounts) | Start is inclusive; end is exclusive. Pending is excluded unless requested and supported. |
| [v2 Account and Transaction](https://www.simplefin.org/protocol.html#account) | These core meanings remain. Currency belongs to the account; custom currencies are possible. Optional `extra` is server-defined. No standard principal, interest, payment-allocation, liability-sign, reversal-link, revision, deletion, or FX-rate fields are defined. |
| [v2 topology and errors](https://www.simplefin.org/protocol.html#account-set) | Connections and `conn_id` replace nested organization identity; `errlist` replaces deprecated `errors`. [`act.missingdata`](https://www.simplefin.org/protocol.html#error) identifies incomplete transactions. |
| [Bridge developer guide](https://beta-bridge.simplefin.org/info/developers) | Intended for daily updates; requests span at most 90 days, while available history varies by institution. The guide recommends about five days of overlap to avoid missing transactions. |

**Version ambiguity:** the current page labels itself `2.0.0-draft`; [`/info`](https://www.simplefin.org/protocol.html#get-info) warns advertised versions may lack draft features. The v1 page is headed `1.0.7`, retains a draft warning, and lists `account`/`balances-only` while its changelog calls them v2 additions. Consequently these pages do not establish deployed feature support. No provider endpoint was queried here. [v1 version warning](https://www.simplefin.org/protocol-v1.html#get-info), [v1 changelog](https://www.simplefin.org/protocol-v1.html#changes), [v2 request version selection](https://www.simplefin.org/protocol.html#get-accounts).

**Research inference:** a description and signed amount identify neither a principal allocation nor the quantity represented by `balance`. An error-free response, a repeated response, or an arithmetic fit to one observed balance cannot independently prove a complete economic history.

## What institution documentation adds

Morgan Stanley's public *Important Account Information for Full-Service Accounts*, **06/2026 edition, page 32**, describes LAL fixed- and variable-rate advances. It says interest is capitalized monthly unless otherwise instructed; payment behavior depends on loan structure and duration. This verifies that capitalization is a documented product possibility. It does not establish the actual account's instructions, agreement, component values, or SimpleFIN mapping. [Current public booklet](https://www.morganstanley.com/wealth/relationshipwithms/pdfs/important_account_information.pdf#page=32).

The live PDF was inspected, rather than relying on the search result's older edition label. Public product documentation is insufficient to equate the provider balance with principal, payoff, or principal plus accrued interest. Those remain account-specific evidence questions.

## What the existing private investigation establishes

These are **reported findings**, limited to the recorded investigation; the linked source requires authorized private access.

| Recorded status | Evidentiary limit |
| --- | --- |
| Latest diagnostic reports raw provider evidence inspected, an importer classification defect, and a Loan balance-model defect. | This research did not receive or rerun that evidence packet. The comment does not establish institution-wide transaction semantics. |
| No importer sign defect was confirmed. | This is not a proof that every importer sign is correct. |
| Interest-inclusive liability is indicated; the exact dated component match remains unverified. | Neither principal-only nor a specific principal-plus-interest equation has been independently accepted. |
| Synthetic source-method failures were reported. | They support the reported diagnosis, not a reproduced historical household reconciliation. |

Source: latest diagnostic in [Expose Sure ledger semantics via read-only MCP and complete LAL reconciliation](https://github.com/RausserHQ/homelab-platform/issues/2102#issuecomment-5849754715).

An earlier guarded reconciliation failed its historical boundary and stopped without the proposed financial edits; repeat-sync acceptance was not completed. That remains a warning against treating a plausible row correction as a reconciled history. [Recorded guard result](https://github.com/RausserHQ/homelab-platform/issues/2102#issuecomment-5848450138).

The record supplies no independent acceptance packet here for reversals, combined-payment allocation, cross-currency behavior, or every liability type. Its absence is an evidence gap, not a finding that those cases are broken.

## Quantities that acceptance examples must name

The following are analytical distinctions, not proposed application fields:

- **Principal (`P`):** the lender-defined outstanding principal at a specified time. Establish whether it already includes capitalized interest; original cash borrowed is a different quantity.
- **Unpaid interest (`I`):** interest accrued or charged but not yet paid or capitalized. Establish whether unbilled accrual is included.
- **Other amounts (`F`):** explicitly identified fees or other obligations included in the selected liability quantity. Escrow and cash collateral need their own stated treatment.
- **Total under an example's definition (`L`):** only if independently supported, `L = P + I + F`. This is not an asserted formula for a SimpleFIN balance.
- **Cash movement:** money received or paid by a particular account. Its direction does not by itself identify principal movement or household income/expense.

For a synthetic example already including unpaid interest in `L`, accrual can increase `I` and `L` without changing `P`. Paying that interest from external cash reduces `I` and `L`. Capitalizing it transfers the amount from `I` into `P`, leaving `L` unchanged at that instant. If interest was previously outside the observed quantity, its later inclusion changes that quantity. These possibilities require different evidence despite a common description containing “interest.”

## Event evidence and unknowns matrix

All effects below are conditional analytical examples. Names, signs, apparent matches, and imported classifications are clues; independent component or allocation evidence supplies the expected effect.

| Event family | Minimum evidence for a balance effect | What that can establish | What remains unproved by a name/sign alone |
| --- | --- | --- | --- |
| Principal advance | Draw confirmation plus dated principal observations; identify net proceeds and any financed charges. | Confirmed principal draw increases `P`; recipient evidence independently establishes cash received. | Whether one feed row is the draw, its cash proceeds, an internal accounting leg, or a correction; whether fees are embedded. |
| Principal repayment | Lender allocation or independently reconciled principal rollforward; paying-account evidence where relevant. | Only the amount applied to principal reduces `P`. | Entire payment equals principal; cash debit alone proves lender application; positive deposit always reduces every liability quantity. |
| Payroll/direct deposit | Pay statement showing net disbursements and destination evidence; lender allocation for any direct application to debt. | Receipt and any principal reduction are separately demonstrable; split destinations can be checked against one net-pay total. | A deposit is payroll; a payroll-looking credit is all principal; linked accounts cover all disbursements; a later sweep is another income receipt. |
| Interest accrual/charge | Dated interest statement or calculation reconciled to lender observations, including billing cutoff. | Unpaid interest change; its effect on an explicitly interest-inclusive quantity. | A cash payment happened; principal increased; the provider includes unbilled interest. |
| Interest payment | Lender interest allocation and funding source, with relevant before/after components. | Interest settlement, distinct from principal reduction; if financed by a new draw, that draw needs separate evidence. | An “interest” row is an expense cash debit, accrual, or capitalization; absence of principal movement means no liability movement. |
| Interest capitalization | Statement identifying capitalization and principal/interest components around it. | Transfer into contractual principal; whether total liability changed depends on its earlier scope and concurrent accrual. | New cash was borrowed or paid; both component movements should increase total debt. |
| Card payment | Source and card-side evidence, or issuer confirmation if one leg is unavailable; identify fees and any borrowing source. | Card liability reduction and source-account effect separately. A line-funded payment can increase line principal while reducing card debt. | Checking cash necessarily funded it; the same amount belongs to this counterpart; a missing card leg proves spending or proves a transfer. |
| Reversal/refund/correction | Link to the original economic event and lender's reversed components, effective/posting times, and any replacement. | Which earlier effects are undone, retained, or replaced. | Opposite equal amounts are related; every component reverses; omission means deletion; reversal and replacement are new borrowing. |
| Combined payment | Statement allocation among principal, interest, fees, escrow/other components; reconcile their sum to cash paid. | Separate component effects under the example's named quantities. | A scheduled amortization split is the actual split; cash total, interest expense, and principal reduction are interchangeable. |

## Boundaries that change what the evidence proves

These are research deductions and acceptance conditions, not product policies.

1. **Observed instant versus reporting day.** Record provider `balance-date`, fetch time, event occurrence, posting, and statement cutoff separately. A fetched value cannot establish a later day-close value. Specify timezone and cutoff when converting instants to dates; test midnight and shared-timestamp events. A date-only statement supports only the boundary it describes.
2. **Request interval versus included economic activity.** Record request bounds and inclusion flags. The documented interval does not specify a complete effective-date ledger or how every server filters optional occurrence times. Test boundary membership with retained evidence; do not infer it from the application's chosen date.
3. **Pending versus posted.** Determine whether each named balance includes pending obligations or holds. Excluding pending rows does not independently prove that the balance excludes their effects. Establish pending-to-posted identity and changed amounts from successive evidence, including when no matching identifier is supplied.
4. **Missing history and missing accounts.** Reconcile an inventory of expected accounts and a bounded statement period. Empty activity can mean unavailable history. Overlap improves collection but is not a completeness certificate; balanced missing pairs can leave endpoint totals unchanged. An unexplained residual identifies disagreement, not its cause.
5. **Corrections and replay.** A no-reuse ID rule is not an immutability or deletion protocol. To test idempotence, retain successive snapshots of the same covered interval, including modifications, disappeared pending items, reversal/replacement, and late postings. Expected outcomes must come from the independent event record. A second identical snapshot alone tests only identical replay.
6. **Currency.** State the unit of each quantity and component. A foreign purchase amount, account-currency settlement, and reporting-currency conversion can differ. Prove actual settlement, rate/date, rounding, and fees where relevant; an external market rate cannot prove the institution's settlement. No cross-currency equality follows from equal-looking numbers.
7. **Observed versus projected.** Amortization computes an expectation under assumed rates, timing, payment application, and fees. A projection is not evidence that an actual payment followed those assumptions. Reconcile any proposed split to statement components before treating it as observed.

## Minimum packet for independent acceptance

This describes evidence needed in later authorized work. Provider records and user-supplied statements can both contribute; authority and conflict handling remain human decisions.

- **Meaning:** the relevant account/product terms or explicit institution explanation identifying each balance quantity, included components, sign meaning, interest treatment, and effective interval. A user interpretation can be recorded as an assertion; it cannot silently become institution verification.
- **Two independent boundaries:** opening and closing values for the same named quantities and currency, with a known cutoff and all intervening activity. Add a boundary with no relevant activity to detect date shifts; account for interest accrual even when there are no transactions.
- **Event detail:** for each matrix family being accepted, independently supplied amount allocation and provenance; source/destination evidence for linked movements; all split-payroll destinations for a coverage claim.
- **Provider comparison:** already-retained raw observations, relevant extension definitions, identity scope, request window, error state, pending flag, and observation/posting times. Compare to the independent source without manufacturing the expected answer from imported classifications.
- **Lifecycle:** at least one repeated observation, one correction or reversal/replacement, and a pending transition where claimed supported; account for duplicates and omitted data explicitly. An empty-history case needs an independent statement that distinguishes no activity from unknown coverage.
- **Reviewable result:** expected component effects and endpoint values derived outside the application under test; compare balance history and reporting claims separately. Preserve private originals privately and publish synthetic cases with equivalent relationships, not scaled or shifted household records.

### Synthetic checks this packet should enable

These invented values demonstrate distinctions; they do not encode the motivating household.

| Case | Independently specified inputs | Expected arithmetic to verify |
| --- | --- | --- |
| Draw then repayment | `P=1,000`; draw `200`; explicitly principal-only repayment `80`; no other changes. | `P=1,120`. Receipt and payment cash legs remain separate evidence. |
| Accrual, capitalization, payment | Initially `P=1,000`, `I=0`; accrue `12`; capitalize `12`; later repay `20` of principal. | For `L=P+I`: `1,000 -> 1,012 -> 1,012 -> 992`; `P` changes only at capitalization and repayment. |
| Payroll allocation | Net disbursement `900`; cash destination `600`; lender confirms `300` applied to principal. | Disbursements total `900`; cash increases `600`; `P` decreases `300`. Reporting presentation is a separate decision. |
| Combined payment | Cash payment `120`; allocation `90` principal, `20` previously owed interest, `10` escrow outside `L`. | `P` decreases `90`; `I` decreases `20`; `L=P+I` decreases `110`, not `120`. |
| Loan-funded card payment | Lender confirms new draw `50`; card issuer confirms payment `50`; no fees. | Line principal increases `50`; card liability decreases `50`; aggregate liability unchanged. |
| Reversal and replay | An advance of `40`, its full reversal, and a replacement advance of `35`, with independent linkage. | Net principal increase `35`; replaying the same record changes nothing further. |

## Precise remaining evidence task

**Question:** For the motivating line of credit, which independently named quantity does each retained SimpleFIN balance represent, and do independently allocated events explain that same quantity between matched boundaries?

**Minimum additional evidence:** two dated lender statements or authenticated user-supplied exports showing principal and unpaid interest/fees separately; the applicable capitalization/payment instructions; event allocations for draws, payroll application, principal and interest payments, and card-funded movements; retained provider observations covering the same instants and interval. Include a no-activity boundary and a repeat/correction observation. If only daily statements exist, constrain the acceptance claim to their documented daily cutoffs.

**Why it matters now:** this blocks an evidence-grounded choice among arithmetic interpretations for the motivating account, and blocks claiming that account is independently accepted. It is not merely a production deployment check. Research into shared behavior and human decisions about evidence authority can proceed while this packet is unavailable; any design conclusion that depends on the unresolved quantity must state that dependency.

This task requires a separately authorized evidence collection or user-supplied packet. This report neither requests provider access nor carries authorization from the archived investigation.

## Open human decisions

The sources do not choose these outcomes:

1. Which quantities and reporting views the product promises to show, including principal, total liability, cash flow, income, spending, and projections.
2. What authority to give provider observations, lender statements, user assertions, and inferred classifications when they disagree; how corrections are reviewed and superseded.
3. Which timestamp and cutoff governs each view, and how pending activity or intraday observations affect it.
4. What to show when coverage, allocation, or balance meaning is unknown; what confidence or limitations users need to see.
5. How to report principal, interest, borrowing, payroll applied to debt, and transfers consistently without counting the same economic event twice.
6. What evidence is sufficient to generalize a product-specific interpretation to another institution, liability type, or period; what event invalidates that interpretation.
7. Which currency conversion source, effective date, rounding, and fee treatment applies to reports, separately from proving actual settlement.

## Research completion and limits

The documented guarantees, attributed diagnostic status, event evidence requirements, and unresolved questions are now explicit. The remaining uncertainty is evidence needed for later acceptance and decisions, not a missing protocol rule that can be recovered by guessing from descriptions.

Only this Markdown asset was changed. No provider requests, credential access, production access, finance mutations, application changes, or tests were performed. Source/history implementation review belongs to the separate research task. This report does not validate application behavior or authorize historical repair.
