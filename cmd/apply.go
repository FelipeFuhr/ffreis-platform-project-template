package cmd

import (
	"fmt"
	"os"
	"strconv"

	"github.com/spf13/cobra"
)

var applyAutoApprove bool

var applyCmd = &cobra.Command{
	Use:   "apply",
	Short: "Provision all infrastructure for the given environment",
	Long: `apply runs terraform apply, creating or updating all managed infrastructure.

State is stored in the bootstrap-managed S3 bucket and locked via DynamoDB.`,
	RunE: func(cmd *cobra.Command, _ []string) error {
		ctx := cmd.Context()
		out := newCommandOutput(cmd, d.ui)

		root, err := repoRoot()
		if err != nil {
			return err
		}
		stack, err := stackDir()
		if err != nil {
			return err
		}

		out.Header("Platform Project Apply", envAccountRegionSummary(d.env, d.accountID, d.region))
		out.Summary("Context", "stack="+stack, "auto-approve="+strconv.FormatBool(applyAutoApprove))
		out.Blank()

		if err := ensureInit(ctx, stack, root, d.env, d.creds); err != nil {
			return fmt.Errorf("terraform init: %w", err)
		}

		d.log.Info("running terraform apply", "env", d.env, "auto_approve", applyAutoApprove)

		args := append([]string{"apply"}, varFileArgs(stack, root, d.env)...)
		if applyAutoApprove {
			args = append(args, "-auto-approve")
		}

		code, err := runTerraform(ctx, runOptions{
			stackPath: stack,
			args:      args,
			creds:     d.creds,
			stdin:     os.Stdin,
		})
		if err != nil {
			return err
		}
		if code != 0 {
			return fmt.Errorf("terraform apply exited with code %d", code)
		}

		d.log.Info("apply complete")
		out.Blank()
		out.Status("ok", "ok", "terraform apply complete")
		return nil
	},
}

func init() {
	applyCmd.Flags().BoolVar(&applyAutoApprove, "auto-approve", false, "Skip interactive approval")
	rootCmd.AddCommand(applyCmd)
}
