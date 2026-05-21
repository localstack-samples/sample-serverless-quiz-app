# Existing Infrastructure — Quiz Platform

Reference doc for engineers building new services against the quiz app's
backend. Numbers/names are accurate as of the most recent deploy of
`bin/deploy.sh`. Always verify with `aws ...` before assuming a resource
is still around — these may drift.

Region: **`us-east-1`**.
Account ID: discoverable via `aws sts get-caller-identity` (it's a
12-digit test account used for this platform).

## DynamoDB tables

### `Quizzes`

The catalog of available quizzes. Created by `CreateQuizFunction`.

| Attribute     | Type   | Notes                                          |
|---------------|--------|------------------------------------------------|
| `QuizID`      | S (PK) | Random `adjective-noun-verb` slug              |
| `Title`       | S      | Display name                                   |
| `Visibility`  | S      | `Public` or `Private`                          |
| `EnableTimer` | BOOL   |                                                |
| `TimerSeconds`| N      | Optional, only when `EnableTimer = true`       |
| `Questions`   | L      | List of question maps (see below)              |

Each question map:

```
{
  "QuestionText": "string",
  "Options":      ["A. ...", "B. ...", "C. ...", "D. ..."],
  "CorrectAnswer":"string (matches one of Options)",
  "Trivia":       "string"
}
```

### `UserSubmissions`

User-submitted quiz responses, post-scoring. Written by `ScoringFunction`
after it pulls a message off `QuizSubmissionQueue`.

| Attribute       | Type   | Notes                                           |
|-----------------|--------|-------------------------------------------------|
| `SubmissionID`  | S (PK) | UUID4                                           |
| `QuizID`        | S      | FK to `Quizzes`                                 |
| `Username`      | S      |                                                 |
| `Score`         | N      | Range key on `QuizID-Score-index` GSI           |
| `Answers`       | M      | Map keyed by question index (as a string)       |
| (optional) `Email` | S   | Present if the submitter opted in to email      |

`Answers` shape:

```
{
  "0": { "Answer": "A. Iron Man", "TimeTaken": 9 },
  "1": { "Answer": "C. Batman",   "TimeTaken": 7 },
  ...
}
```

`TimeTaken` is seconds (number, can be float).

GSI: `QuizID-Score-index` — `QuizID` (HASH) + `Score` (RANGE). Used by
`GetLeaderboardFunction`.

**Streams: not enabled by default.** If you need to react to inserts,
enable streams with `aws dynamodb update-table --stream-specification
StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES`.

## Lambda functions

All Python 3.10. All have IAM roles named `<Function>Role`. All sit on
the same VPC-less default config.

| Function                       | Purpose                                                | Trigger                |
|--------------------------------|--------------------------------------------------------|------------------------|
| `CreateQuizFunction`           | `POST /createquiz` → writes to `Quizzes`               | API Gateway            |
| `GetQuizFunction`              | `GET /getquiz`                                         | API Gateway            |
| `ListPublicQuizzesFunction`    | `GET /listquizzes`                                     | API Gateway            |
| `SubmitQuizFunction`           | `POST /submitquiz` → SQS                               | API Gateway            |
| `ScoringFunction`              | reads SQS, scores, writes to `UserSubmissions`         | SQS event source       |
| `GetSubmissionFunction`        | `GET /getsubmission`                                   | API Gateway            |
| `GetLeaderboardFunction`       | `GET /getleaderboard` (uses GSI)                       | API Gateway            |
| `RetryQuizzesWritesFunction`   | retries failed `Quizzes` writes after DDB outages      | SNS → SQS event source |

The source code for each lives in `lambdas/<function>/handler.py` in
this repo.

## SQS queues

- `QuizSubmissionQueue` — main submission queue, drained by
  `ScoringFunction`. Has a redrive policy to `QuizSubmissionDLQ`
  (maxReceiveCount=1).
- `QuizSubmissionDLQ` — dead letter for the above. Bridged to
  `DLQAlarmTopic` (SNS) via an EventBridge Pipe.
- `QuizzesWriteFailuresQueue` — receives messages from the
  `QuizzesWriteFailures` SNS topic when `CreateQuizFunction` fails to
  write to DDB during a chaos test. Drained by `RetryQuizzesWritesFunction`.

## SNS topics

- `DLQAlarmTopic` — DLQ alert fan-out. One email subscription
  (your.email@example.com — placeholder).
- `QuizzesWriteFailures` — used during chaos engineering scenarios.

## API Gateway

REST API named `QuizAPI`. Pull the ID with:

```bash
aws apigateway get-rest-apis --query "items[?name=='QuizAPI'].id" --output text
```

Stage: `prod`. Base URL:
`https://<host>/_aws/execute-api/<api-id>/prod`. (The host is a
platform detail — the API endpoint is set up by the platform team.)

Routes:

| Route                  | Method | Function                       |
|------------------------|--------|--------------------------------|
| `/createquiz`          | POST   | `CreateQuizFunction`           |
| `/getquiz`             | GET    | `GetQuizFunction`              |
| `/submitquiz`          | POST   | `SubmitQuizFunction`           |
| `/getsubmission`       | GET    | `GetSubmissionFunction`        |
| `/getleaderboard`      | GET    | `GetLeaderboardFunction`       |
| `/listquizzes`         | GET    | `ListPublicQuizzesFunction`    |

## Step Functions

- `SendEmailStateMachine` — orchestrates SES emails to users who opted
  in. Triggered by `ScoringFunction` when it sees `Email` on a
  submission. Don't touch.

## CloudFront

One distribution serves the static React frontend from S3. Frontend
calls the API Gateway directly. You don't need to interact with this
for backend work.

## Discovery cheat sheet

```bash
# Who am I
aws sts get-caller-identity

# Tables + their stream state
aws dynamodb list-tables
aws dynamodb describe-table --table-name UserSubmissions \
  --query 'Table.[TableName,StreamSpecification,LatestStreamArn]'

# Lambdas + their roles
aws lambda list-functions \
  --query 'Functions[].[FunctionName,Role,Runtime,Architectures]' \
  --output table

# What can a given role do?
aws iam list-attached-role-policies --role-name ScoringRole
aws iam list-role-policies --role-name ScoringRole
aws iam get-policy-version \
  --policy-arn arn:aws:iam::<account>:policy/ScoringFunctionPolicy \
  --version-id v1 --query 'PolicyVersion.Document'

# Queues
aws sqs list-queues
aws sqs get-queue-attributes --queue-url <url> --attribute-names All

# API Gateway
aws apigateway get-rest-apis
aws apigateway get-resources --rest-api-id <id>
```
