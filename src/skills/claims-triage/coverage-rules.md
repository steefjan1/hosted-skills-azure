# Coverage rules

Use the `coverages` object on the policy. Each entry has a `limit` and a `description`.

- `covered: yes` when the question maps to a coverage line on the policy and the amount,
  if given, is within the limit after the deductible.
- `covered: partial` when the line exists but the amount exceeds the limit, or the line
  reimburses a percentage (dental `restorative` pays 75%).
- `covered: no` when the line is absent from the policy, or its limit is 0, or the
  policy status is not `active`.
- `covered: unknown` when the policy does not exist or the question is not about a
  coverage line.

Name the coverage line you used in `coverage` and quote the limit in `limit`. The
deductible applies once per claim to car policies and never to dental policies.
