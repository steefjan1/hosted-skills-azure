# Severity rubric

Inputs: the policy (from `policy_lookup`), the claim history (from `claim_history`) and the
signal list with its total `score` (from `fraud_signals`).

## Severity and route

| Condition (first match wins) | Severity | Route |
|---|---|---|
| Policy not found, or policy status is not `active` | high | investigator |
| Signal score 4 or higher | high | investigator |
| Signal score 2 or 3, or claim amount 5,000 or more | medium | adjuster |
| Anything else | low | auto_approve |

## Rationale

Two sentences. The first names the signal score and the amount. The second lists at most
three signal details, or says that no signals were raised.

## Signal codes you will see

| Code | Weight | Meaning |
|---|---|---|
| unknown_policy | 3 | The policy number does not exist |
| policy_not_active | 3 | Lapsed or cancelled policy |
| new_policy | 2 | Incident within 30 days of the policy start date |
| coverage_not_on_policy | 2 | The claimed coverage line is not on the policy |
| amount_over_limit | 1 | Amount exceeds the coverage limit |
| late_report | 1 | Reported more than 30 days after the incident |
| high_amount | 1 | Amount of 10,000 or more |
| frequent_claimant | 1 | Two or more claims since 2025 |
| prior_rejection | 1 | An earlier claim on the policy was rejected |
