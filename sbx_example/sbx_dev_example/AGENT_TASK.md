# Task: Quiz Submission Analytics Pipeline

You are a backend engineer joining the Quiz Platform team. The product
already ships a fully serverless quiz app on AWS — users browse public
quizzes, submit their answers through an API Gateway, and a scoring
pipeline writes results to DynamoDB.

The team now wants **per-submission analytics**. Every time a user finishes
a quiz, we want to capture how they actually answered it — not the score
(scoring is already handled by `ScoringFunction`), but the *behavior*:
how fast they were on each question, where they hesitated, total time spent.
Product wants this data in a separate table so they can build dashboards
without coupling to the live submission path.

Your job: build that pipeline and deploy it to the existing AWS account.

## Deliverables

All of the following must end up in `sbx_example/sbx_dev_example/` in
this repository:

1. **`lambda/handler.py`** — a Python 3.10 Lambda function
   (`QuizAnalyticsFunction`).
2. **`deploy.sh`** — an idempotent shell script that, when re-run against
   the existing account, brings the analytics pipeline to the desired
   state (creates resources if missing, no-ops if already there).
3. **`README.md`** — short doc covering: what you built, what IAM you
   provisioned and why, how to deploy, how to verify.

You can add other files as needed (policy JSON, requirements.txt, etc.).

## Functional requirements

The lambda must:

- Be triggered automatically whenever a new item is written to the
  `UserSubmissions` DynamoDB table. (DynamoDB Streams is the obvious
  pick; if the table doesn't have streams enabled yet, you'll need to
  enable them — that's part of the work.)
- For each new submission, compute and persist:
  - `SubmissionID` (carry-through, matches the source row)
  - `QuizID` (carry-through)
  - `Username` (carry-through)
  - `NumQuestions` — count of questions answered
  - `TotalTimeSeconds` — sum of `TimeTaken` across all answers
  - `AverageTimePerQuestion` — total / N, rounded to 2 decimals
  - `FastestAnswerSec` — min `TimeTaken`
  - `SlowestAnswerSec` — max `TimeTaken`
  - `HesitationIndex` — `SlowestAnswerSec / AverageTimePerQuestion`
    (a rough "did they get stuck on one question" signal)
  - `ProcessedAt` — ISO-8601 UTC timestamp when the analytics row was
    written
- Write all of the above to a new DynamoDB table named **`QuizAnalytics`**
  (you choose the key schema — pick one that supports both
  "look up by submission" and "list everything for a given quiz"
  efficiently).
- Be safe to invoke twice on the same source record (idempotent on
  `SubmissionID`).

## Existing infrastructure (summary)

See `INFRASTRUCTURE.md` in this directory for the rundown of what's
already deployed in the account. The short version:

- `Quizzes` and `UserSubmissions` DynamoDB tables already exist.
- The submission flow is `POST /submitquiz` → SQS → `ScoringFunction`
  (Lambda) → writes the scored row to `UserSubmissions`.
- Several Lambda IAM roles already exist (one per function). Some have
  permissions you can borrow from; none have exactly what *you* need.
- The API Gateway is named `QuizAPI`. Don't touch its routes — this
  pipeline is purely backend, no new HTTP surface.

## Discovery — do this before writing any code

Before you start writing, take 10 minutes to actually inspect the account.
Don't trust the summary — verify it:

```bash
aws sts get-caller-identity
aws dynamodb list-tables
aws dynamodb describe-table --table-name UserSubmissions
aws lambda list-functions --query 'Functions[].FunctionName'
aws iam list-roles --query 'Roles[?starts_with(RoleName, `Quiz`) || ends_with(RoleName, `Role`)].RoleName'
```

In particular: **figure out whether `UserSubmissions` already has streams
enabled, and what `ScoringRole` is allowed to do.** That tells you
whether you can plagiarize from an existing role or have to write fresh
IAM.

You should also look at the source of one of the existing handlers
(e.g. `lambdas/scoring/handler.py`) to understand what fields are
present on a `UserSubmissions` row — particularly the shape of
`Answers`, which is what your math runs on.

## IAM — your call, defend it

The lambda needs (at minimum):
- Read permissions on the `UserSubmissions` stream.
- Write permissions on the `QuizAnalytics` table.
- CloudWatch Logs.

You have two reasonable options:

- **Reuse `ScoringRole`** — it already has read on `UserSubmissions` and
  may have write somewhere too. Add a policy for the new table + the
  stream. Pro: less to manage. Con: blurs scoring vs. analytics
  separation and grants ScoringFunction extra permissions it doesn't
  need.
- **Create a dedicated `QuizAnalyticsRole`** — fresh trust policy,
  least-privilege inline (or attached) policy. Pro: clean. Con: more
  bash.

Pick one, document the reasoning in your `README.md`. There isn't a
"correct" answer — we want to see your judgment.

## Tools & conventions

- Use the AWS CLI (`aws`) for all infrastructure operations. boto3
  inside the lambda. Region is `us-east-1`. Account ID you can pull
  from `aws sts get-caller-identity`.
- Lambda runtime: `python3.10`. Match the host CPU architecture —
  check `uname -m`; if it's `aarch64` set `--architectures arm64`,
  otherwise `x86_64`. (Wrong architecture causes silent runtime
  init failures.)
- Make `deploy.sh` re-runnable. Use `aws ... 2>/dev/null || true`
  for create operations that fail when the resource exists, and
  `aws ... update-table` etc. to converge config.
- Keep all your files inside `sbx_example/sbx_dev_example/`. Do not
  edit `bin/deploy.sh` or anything else under `lambdas/` or `bin/`.

## Acceptance criteria

When you say "done", a reviewer will:

1. Confirm `sbx_example/sbx_dev_example/deploy.sh` runs cleanly on a
   fresh deploy of the quiz app, and runs cleanly *again* without
   errors (idempotency check).
2. Confirm a new row appears in `QuizAnalytics` for each existing row
   in `UserSubmissions` (you may need to trigger backfill, or just
   submit a new quiz response via the API).
3. Spot-check the math on one row by reading the source `Answers` dict
   and recomputing `AverageTimePerQuestion` / `HesitationIndex` by hand.
4. Inspect the IAM you provisioned and confirm it makes sense.

## What to ask vs. what to figure out

Things to figure out by inspecting the account:
- Stream ARN for `UserSubmissions` (after you enable streams).
- Existing IAM role/policy shapes.
- The structure of `Answers` (a dict; keys are question indexes as
  strings; values are `{Answer, TimeTaken}`).

Things to ask the user before doing:
- Anything that changes the existing quiz pipeline (don't, unless
  asked).
- Anything that touches IAM outside the new role you create
  (don't widen any existing role unless explicitly approved).

Start with discovery. Show your work in the chat as you go.
