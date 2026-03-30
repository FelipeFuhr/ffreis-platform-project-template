// Package test contains Terratest integration tests for platform-project-template.
//
// Tests deploy real AWS resources in the dev environment and destroy them after.
// Required environment variables:
//
//	AWS_TEST_ROLE_ARN      — IAM role Terratest assumes via OIDC
//	TEST_BACKEND_BUCKET    — S3 bucket used for isolated test Terraform state
//	TEST_BACKEND_LOCK_TABLE — DynamoDB table for state locking (optional)
//
// Optional:
//
//	AWS_TEST_REGION        — AWS region (default: us-east-1)
//
// Run all tests:
//
//	go test -v -timeout 30m ./...
//
// Run a single test:
//
//	go test -v -timeout 30m -run TestProjectStack ./...
package test

import (
	"context"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
)

const (
	// testPrefix is prepended to every resource name created by tests.
	// Use it to identify and bulk-clean up leaked resources if a test crashes.
	testPrefix = "tftest"

	// defaultRegion is used when AWS_TEST_REGION is not set.
	defaultRegion = "us-east-1"
)

// testRegion returns the AWS region for tests.
// Override with AWS_TEST_REGION env var.
func testRegion() string {
	if r := os.Getenv("AWS_TEST_REGION"); r != "" {
		return r
	}
	return defaultRegion
}

// testTags returns standard tags applied to every resource created by tests.
// These tags allow cost attribution and emergency bulk cleanup via tag policies.
func testTags() map[string]interface{} {
	return map[string]interface{}{
		"ManagedBy":   "terratest",
		"Environment": "test",
		"Repository":  "platform-project-template",
	}
}

// skipIfNoCredentials skips the test if no AWS credentials are configured.
// This allows the test suite to run in CI without AWS access (tests are skipped,
// not failed) and only execute when credentials are explicitly provided.
func skipIfNoCredentials(t *testing.T) {
	t.Helper()

	ctx := context.Background()
	_, err := config.LoadDefaultConfig(ctx, config.WithRegion(testRegion()))
	if err != nil {
		t.Skipf("skipping: AWS credentials not configured: %v", err)
	}

	// Require an explicit test role to prevent accidental use of production credentials.
	if os.Getenv("AWS_TEST_ROLE_ARN") == "" && os.Getenv("AWS_ACCESS_KEY_ID") == "" {
		t.Skip("skipping: set AWS_TEST_ROLE_ARN or AWS_ACCESS_KEY_ID to run integration tests")
	}
}

// resourceName generates a unique, prefixed resource name safe for use in
// AWS resource identifiers. The result is always lowercase and ≤ 32 chars
// to satisfy project_name validation.
func resourceName(uniqueID string) string {
	name := fmt.Sprintf("%s-%s", testPrefix, strings.ToLower(uniqueID))
	if len(name) > 32 {
		name = name[:32]
	}
	return name
}

// testBackendConfig returns the BackendConfig map for an isolated test state key.
// Skips the test if TEST_BACKEND_BUCKET is not set.
func testBackendConfig(t *testing.T, uniqueID string) map[string]interface{} {
	t.Helper()
	bucket := os.Getenv("TEST_BACKEND_BUCKET")
	if bucket == "" {
		t.Skip("skipping: TEST_BACKEND_BUCKET not set — required for stack integration tests")
	}
	bc := map[string]interface{}{
		"bucket":  bucket,
		"key":     fmt.Sprintf("test/%s/terraform.tfstate", uniqueID),
		"region":  testRegion(),
		"encrypt": true,
	}
	if table := os.Getenv("TEST_BACKEND_LOCK_TABLE"); table != "" {
		bc["dynamodb_table"] = table
	}
	return bc
}
