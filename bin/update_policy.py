#!/usr/bin/env python

"""
Simple script that allows enabling/disabling access from the sample app's Lambda
functions to the DynamoDB tables, by removing/adding permissions from/to the role
policy that manages access.
This can be handy to showcase IAM enforcement in LocalStack (IAM soft mode and hard mode).
"""

import json
import os
import sys

import boto3

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")
iam_client = boto3.client("iam", endpoint_url="https://localhost.localstack.cloud:4566")


def update_role_policy(allow: bool):
    roles = iam_client.list_roles()
    for role in roles["Roles"]:
        in_scope = (
            "QuizAppStack-ScoringFunctionLambdaFun" in role["RoleName"]
            or "QuizAppStack-ListPublicQuizzes" in role["RoleName"]
            or "QuizAppStack-" in role["RoleName"]
        )
        if not in_scope:
            continue

        # list policies for this role
        response = iam_client.list_role_policies(RoleName=role["RoleName"])
        for policy_name in response["PolicyNames"]:
            response = iam_client.get_role_policy(
                RoleName=role["RoleName"], PolicyName=policy_name
            )
            # get the policy document
            policy_doc = response["PolicyDocument"]
            # remove all policies that contain a statement with "dynamodb:GetItem"
            policy_doc["Statement"] = [
                stmt
                for stmt in policy_doc["Statement"]
                if "dynamodb:GetItem" not in stmt["Action"]
            ]
            if allow:
                # if we're in `allow` mode, add a statement with the required actions back to the policy
                policy_doc["Statement"].append(
                    {
                        "Action": [
                            "dynamodb:BatchGetItem",
                            "dynamodb:BatchWriteItem",
                            "dynamodb:ConditionCheckItem",
                            "dynamodb:DeleteItem",
                            "dynamodb:DescribeTable",
                            "dynamodb:GetItem",
                            "dynamodb:GetRecords",
                            "dynamodb:GetShardIterator",
                            "dynamodb:PutItem",
                            "dynamodb:Query",
                            "dynamodb:Scan",
                            "dynamodb:UpdateItem",
                        ],
                        "Effect": "Allow",
                        "Resource": [
                            "arn:aws:dynamodb:us-east-1:000000000000:table/Quizzes",
                            "arn:aws:dynamodb:us-east-1:000000000000:table/UserSubmissions",
                            "arn:aws:dynamodb:us-east-1:000000000000:table/UserSubmissions/index/*",
                        ],
                    }
                )

            if not policy_doc["Statement"]:
                # hack/workaround: statement cannot be fully empty, so we're adding a single dummy entry here
                policy_doc["Statement"].append(
                    {
                        "Action": ["dynamodb:ConditionCheckItem"],
                        "Effect": "Allow",
                        "Resource": [
                            "arn:aws:dynamodb:us-east-1:000000000000:table/Quizzes"
                        ],
                    }
                )

            # update the role policy
            iam_client.put_role_policy(
                RoleName=role["RoleName"],
                PolicyName=policy_name,
                PolicyDocument=json.dumps(policy_doc),
            )


def main():
    if len(sys.argv) <= 1 or sys.argv[1] not in ("enable", "disable"):
        raise Exception("Usage: update_policy.py [enable | disable]")
    update_role_policy(allow=sys.argv[1] == "enable")


if __name__ == "__main__":
    main()
