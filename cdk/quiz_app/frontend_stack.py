import os

import aws_cdk
from aws_cdk import (
    Stack,
    Tags,
    aws_s3 as s3,
    aws_cloudfront as cf,
    aws_cloudfront_origins as origins,
    aws_s3_deployment as s3deploy,
    CfnOutput,
)
from constructs import Construct


class FrontendStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        webapp_bucket = s3.Bucket(
            self,
            "WebAppBucket",
            auto_delete_objects=True,
            removal_policy=aws_cdk.RemovalPolicy.DESTROY,
        )
        origin_access_identity = cf.OriginAccessIdentity(self, "OriginAccessIdentity")
        webapp_bucket.grant_read(origin_access_identity)

        # deploy process
        distribution = cf.Distribution(
            self,
            "FrontendDistribution",
            default_root_object="index.html",
            default_behavior=cf.BehaviorOptions(
                origin=origins.S3Origin(
                    webapp_bucket,
                    origin_access_identity=origin_access_identity,
                ),
                viewer_protocol_policy=cf.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            ),
        )

        Tags.of(distribution).add("_custom_id_", "quiz-app")

        s3deploy.BucketDeployment(
            self,
            "DeployApp",
            sources=[
                s3deploy.Source.asset(
                    os.path.join(
                        os.path.dirname(__file__), "..", "..", "frontend", "build"
                    )
                ),
            ],
            destination_bucket=webapp_bucket,
            distribution=distribution,
            distribution_paths=["/*"],
        )

        CfnOutput(self, "DistributionDomainName", value=distribution.domain_name)

