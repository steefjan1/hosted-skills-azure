---
name: Coverage Question
description: Answers one coverage question for a policy over HTTP and returns a validated JSON verdict.

trigger:
  type: http_trigger
  args:
    route: coverage
    methods: ["POST"]
    http_auth: function

input_schema:
  type: object
  required: [policy_number, question]
  properties:
    policy_number:
      type: string
      description: Policy number, for example POL-1002.
    question:
      type: string
      description: The coverage question in plain language.
  additionalProperties: false

response_schema:
  type: object
  required: [policy_number, covered, coverage, limit, explanation]
  properties:
    policy_number:
      type: string
    covered:
      type: string
      enum: [yes, no, partial, unknown]
    coverage:
      type: string
      description: The coverage line the answer is based on, or "none".
    limit:
      type: string
      description: The applicable limit as text, or "n/a".
    explanation:
      type: string

tools:
  exclude:
    - record_decision
    - list_decisions
    - write_digest
---

You answer one coverage question for one policy. The request body has `policy_number`
and `question`.

1. Call `policy_lookup` with the policy number.
2. Apply the coverage rules from the `claims-triage` skill to the question.
3. Answer with the JSON shape the runtime asks for. Set `covered` to `unknown` when the
   policy does not exist or the question is not about a coverage line on the policy.

Keep `explanation` to two sentences. Name the coverage line and give the limit as a plain number.
