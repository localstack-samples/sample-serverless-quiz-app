import aws_cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_cloudfront as cf,
    aws_cloudfront_origins as origins,
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

        # The frontend build isn't synced via s3_deployment.BucketDeployment:
        # that construct's singleton handler shells out to a real, unpatched
        # AWS CLI binary (bundled via AwsCliLayer) to run `aws s3 cp`. LocalStack's
        # Lambda executor unconditionally blanks the AWS_CA_BUNDLE env var for
        # every function (confirmed: even an explicit override on the function's
        # own configuration gets reset), which that unpatched CLI rejects as
        # invalid, so the deployment always fails with "Invalid CA bundle".
        # Instead, bin/deploy_cdk.sh syncs the build to WebAppBucket (below) and
        # invalidates FrontendDistribution directly via `lstk aws`, after this
        # stack deploys.

        CfnOutput(self, "DistributionDomainName", value=distribution.domain_name)
        CfnOutput(self, "WebAppBucketName", value=webapp_bucket.bucket_name)
        CfnOutput(self, "DistributionId", value=distribution.distribution_id)

