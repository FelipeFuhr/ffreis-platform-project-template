package cmd

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	sdkaws "github.com/aws/aws-sdk-go-v2/aws"
)

const (
	testNukeProdConfirm = "nuke-prod\n"
	testNukeCancelInput = "cancel\n"
)

// setupTestDeps configures the package-level dep struct with test values.
// Returns the repo root directory.
func setupTestDeps(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	initRepoLayout(t, root, testEnv)
	withWorkingDir(t, root)

	d.env = testEnv
	d.region = testRegion
	d.accountID = testAccountID
	d.log = newLogger("error")
	d.ui = nil
	d.creds = rawCreds{
		AccessKeyID:     "AKIATEST",
		SecretAccessKey: "secret",
		SessionToken:    "",
		Region:          testRegion,
	}
	d.awsCfg = sdkaws.Config{}
	return root
}

func TestPlanRunsTerraform(t *testing.T) {
	root := setupTestDeps(t)
	stack := filepath.Join(root, stackDirName)

	// Pre-initialise so ensureInit is a no-op.
	if err := os.MkdirAll(filepath.Join(stack, ".terraform"), 0o755); err != nil {
		t.Fatalf(errMkdirTerraform, err)
	}

	setupFakeTerraform(t, `echo "$@" >> ../trace.txt; exit 0`)

	var buf bytes.Buffer
	planCmd.SetContext(context.Background())
	planCmd.SetOut(&buf)
	planCmd.SetErr(&buf)
	if err := planCmd.RunE(planCmd, nil); err != nil {
		t.Fatalf(errUnexpectedError, err)
	}

	traceFile := filepath.Join(root, traceFileName)
	data, err := os.ReadFile(traceFile)
	if err != nil {
		t.Fatalf(errReadTraceFile, err)
	}
	if !strings.Contains(string(data), "plan") {
		t.Errorf("expected terraform plan in trace, got: %s", data)
	}
}

func TestApplyRunsTerraform(t *testing.T) {
	root := setupTestDeps(t)
	stack := filepath.Join(root, stackDirName)

	if err := os.MkdirAll(filepath.Join(stack, ".terraform"), 0o755); err != nil {
		t.Fatalf(errMkdirTerraform, err)
	}

	setupFakeTerraform(t, `echo "$@" >> ../trace.txt; exit 0`)

	applyAutoApprove = true
	defer func() { applyAutoApprove = false }()

	var buf bytes.Buffer
	applyCmd.SetContext(context.Background())
	applyCmd.SetOut(&buf)
	applyCmd.SetErr(&buf)
	if err := applyCmd.RunE(applyCmd, nil); err != nil {
		t.Fatalf(errUnexpectedError, err)
	}

	traceFile := filepath.Join(root, traceFileName)
	data, err := os.ReadFile(traceFile)
	if err != nil {
		t.Fatalf(errReadTraceFile, err)
	}
	if !strings.Contains(string(data), "apply") {
		t.Errorf("expected terraform apply in trace, got: %s", data)
	}
}

func TestNukeConfirmationRequired(t *testing.T) {
	root := setupTestDeps(t)

	setStdinText(t, testNukeCancelInput)
	setupFakeTerraform(t, `echo "$@" >> ../trace.txt; exit 0`)

	var buf bytes.Buffer
	nukeCmd.SetContext(context.Background())
	nukeCmd.SetOut(&buf)
	nukeCmd.SetErr(&buf)
	if err := nukeCmd.RunE(nukeCmd, nil); err != nil {
		t.Fatalf(errUnexpectedError, err)
	}

	// Terraform must not have been invoked.
	if _, err := os.Stat(filepath.Join(root, traceFileName)); err == nil {
		t.Fatal("terraform was called despite wrong confirmation")
	}
}

func TestNukeDestroysOnConfirmation(t *testing.T) {
	root := setupTestDeps(t)

	setStdinText(t, testNukeProdConfirm)
	setupFakeTerraform(t, `echo "$@" >> ../trace.txt; exit 0`)

	var buf bytes.Buffer
	nukeCmd.SetContext(context.Background())
	nukeCmd.SetOut(&buf)
	nukeCmd.SetErr(&buf)
	if err := nukeCmd.RunE(nukeCmd, nil); err != nil {
		t.Fatalf(errUnexpectedError, err)
	}

	traceFile := filepath.Join(root, traceFileName)
	data, err := os.ReadFile(traceFile)
	if err != nil {
		t.Fatalf(errReadTraceFile, err)
	}
	if !strings.Contains(string(data), "destroy") {
		t.Errorf("expected terraform destroy in trace, got: %s", data)
	}
}

func TestVersionCommandPrintsVersion(t *testing.T) {
	d.log = newLogger("error")
	d.ui = nil

	var buf bytes.Buffer
	versionCmd.SetOut(&buf)
	versionCmd.Run(versionCmd, nil)

	if buf.Len() == 0 {
		t.Fatal("expected version output")
	}
}
