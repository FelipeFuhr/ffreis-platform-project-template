package test

import (
	"context"
	"encoding/json"
	"net/url"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestProjectStackIAMRoles deploys the project-template stack in the dev environment
// and verifies that the three least-privilege Terraform deployment roles are created
// with the correct trust policies and naming.
//
// What it tests:
//   - plan role ARN is valid and the role exists in IAM
//   - apply role ARN is valid and the role exists in IAM
//   - destroy role is created for dev (destroy role is dev-only)
//   - plan role trust policy only allows the supplied principal (not a wildcard)
//
// Cost: minimal — IAM roles have no per-resource cost; KMS/CloudTrail/CloudWatch
// resources are destroyed at test end.
// Cleanup: defer terraform.Destroy runs even if assertions fail.
func TestProjectStackIAMRoles(t *testing.T) {
	t.Parallel()
	skipIfNoCredentials(t)

	region := testRegion()
	uniqueID := random.UniqueId()
	projectName := resourceName(uniqueID)

	// Resolve caller identity so the IAM trust policies have a real principal.
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	require.NoError(t, err, "load AWS config")

	stsClient := sts.NewFromConfig(cfg)
	callerID, err := stsClient.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	require.NoError(t, err, "get caller identity")
	callerARN := *callerID.Arn

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../infra/stack",
		BackendConfig: testBackendConfig(t, uniqueID),
		Vars: map[string]interface{}{
			"project_name":           projectName,
			"environment":            "dev",
			"allowed_principal_arns": []string{callerARN},
			"tags":                   testTags(),
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
		RetryableTerraformErrors: map[string]string{
			".*TooManyRequestsException.*": "AWS rate-limiting; retrying",
			".*RequestError.*":             "transient network error; retrying",
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	// ── Output validation ────────────────────────────────────────────────────

	planRoleARN    := terraform.Output(t, terraformOptions, "terraform_plan_role_arn")
	applyRoleARN   := terraform.Output(t, terraformOptions, "terraform_apply_role_arn")
	applyRoleName  := terraform.Output(t, terraformOptions, "terraform_apply_role_name")
	destroyRoleARN := terraform.Output(t, terraformOptions, "terraform_destroy_role_arn")

	assert.True(t, strings.HasPrefix(planRoleARN, "arn:aws:iam::"),
		"terraform_plan_role_arn %q is not a valid IAM ARN", planRoleARN)
	assert.True(t, strings.HasPrefix(applyRoleARN, "arn:aws:iam::"),
		"terraform_apply_role_arn %q is not a valid IAM ARN", applyRoleARN)
	assert.NotEmpty(t, applyRoleName, "terraform_apply_role_name must not be empty")

	// destroy role is created in dev; non-empty means the conditional worked.
	assert.True(t, strings.HasPrefix(destroyRoleARN, "arn:aws:iam::"),
		"terraform_destroy_role_arn must exist in dev environment")

	// ── AWS SDK: verify plan role exists and has a constrained trust policy ──

	iamClient := iam.NewFromConfig(cfg)

	// Extract role name from ARN (last path segment).
	planRoleName := planRoleARN[strings.LastIndex(planRoleARN, "/")+1:]

	roleOut, err := iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: &planRoleName})
	require.NoError(t, err, "get plan role %s", planRoleName)
	require.NotNil(t, roleOut.Role)

	// Trust policy must not allow a wildcard principal.
	policyJSON, err := url.QueryUnescape(*roleOut.Role.AssumeRolePolicyDocument)
	require.NoError(t, err, "URL-decode trust policy")

	var trustPolicy map[string]interface{}
	require.NoError(t, json.Unmarshal([]byte(policyJSON), &trustPolicy))

	stmts, ok := trustPolicy["Statement"].([]interface{})
	require.True(t, ok && len(stmts) > 0, "trust policy must have at least one statement")

	for _, raw := range stmts {
		stmt, ok := raw.(map[string]interface{})
		require.True(t, ok)
		principal := stmt["Principal"]
		// Wildcard principal ("*") would be a security misconfiguration.
		assert.NotEqual(t, "*", principal,
			"plan role trust policy must not allow wildcard principal")
	}

	// ── AWS SDK: verify apply role exists ───────────────────────────────────

	applyOut, err := iamClient.GetRole(ctx, &iam.GetRoleInput{RoleName: &applyRoleName})
	require.NoError(t, err, "get apply role %s", applyRoleName)
	assert.Equal(t, applyRoleName, *applyOut.Role.Name)
}

// TestProjectStackLogging deploys the project-template stack in the dev environment
// and verifies that the CloudTrail S3 bucket and CloudWatch log group are created
// with the expected configuration.
//
// What it tests:
//   - cloudtrail_bucket_name output is non-empty
//   - cloudwatch_log_group_name output is non-empty
//   - S3 bucket exists and has versioning enabled
//   - CloudWatch log group exists with the expected retention
func TestProjectStackLogging(t *testing.T) {
	t.Parallel()
	skipIfNoCredentials(t)

	region := testRegion()
	uniqueID := random.UniqueId()
	projectName := resourceName(uniqueID)

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	require.NoError(t, err, "load AWS config")

	stsClient := sts.NewFromConfig(cfg)
	callerID, err := stsClient.GetCallerIdentity(ctx, &sts.GetCallerIdentityInput{})
	require.NoError(t, err, "get caller identity")

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../infra/stack",
		BackendConfig: testBackendConfig(t, uniqueID),
		Vars: map[string]interface{}{
			"project_name":           projectName,
			"environment":            "dev",
			"allowed_principal_arns": []string{*callerID.Arn},
			"enable_logging":         true,
			"log_retention_days":     30,
			"tags":                   testTags(),
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
		RetryableTerraformErrors: map[string]string{
			".*TooManyRequestsException.*": "AWS rate-limiting; retrying",
			".*RequestError.*":             "transient network error; retrying",
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	// ── Output validation ────────────────────────────────────────────────────

	trailBucket  := terraform.Output(t, terraformOptions, "cloudtrail_bucket_name")
	logGroupName := terraform.Output(t, terraformOptions, "cloudwatch_log_group_name")

	assert.NotEmpty(t, trailBucket, "cloudtrail_bucket_name output must not be empty")
	assert.NotEmpty(t, logGroupName, "cloudwatch_log_group_name output must not be empty")

	// ── AWS SDK: S3 bucket exists with versioning enabled ───────────────────

	s3Client := s3.NewFromConfig(cfg)

	versioningOut, err := s3Client.GetBucketVersioning(ctx,
		&s3.GetBucketVersioningInput{Bucket: &trailBucket})
	require.NoError(t, err, "get versioning for bucket %s", trailBucket)
	assert.Equal(t, "Enabled", string(versioningOut.Status),
		"CloudTrail S3 bucket must have versioning enabled")

	// ── AWS SDK: CloudWatch log group exists with expected retention ─────────

	logsClient := cloudwatchlogs.NewFromConfig(cfg)

	groupsOut, err := logsClient.DescribeLogGroups(ctx,
		&cloudwatchlogs.DescribeLogGroupsInput{LogGroupNamePrefix: &logGroupName})
	require.NoError(t, err, "describe log group %s", logGroupName)
	require.NotEmpty(t, groupsOut.LogGroups,
		"CloudWatch log group %q must exist", logGroupName)

	// At least one log group has the expected name.
	var found bool
	for _, g := range groupsOut.LogGroups {
		if g.LogGroupName != nil && *g.LogGroupName == logGroupName {
			found = true
			// Retention must match the configured value.
			assert.Equal(t, int32(30), *g.RetentionInDays,
				"log group retention must match log_retention_days=30")
			break
		}
	}
	assert.True(t, found, "log group %q not found in describe response", logGroupName)
}
