package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

var nukeCmd = &cobra.Command{
	Use:   "nuke",
	Short: "Destroy all infrastructure for the given environment (IRREVERSIBLE)",
	Long: `nuke initialises terraform and runs destroy -auto-approve.

This is irreversible. State is stored in the bootstrap-managed S3 bucket;
destroying the bootstrap layer before running nuke will prevent clean teardown.

NOTE: Always run nuke before destroying the bootstrap or platform-org layer.
Destroying those first removes the S3 state backend, leaving resources orphaned.`,
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

		out.Header("Platform Project Nuke", envAccountRegionSummary(d.env, d.accountID, d.region))
		out.Blank()
		out.Status("warn", "warn", fmt.Sprintf("this will DESTROY all %s infrastructure", d.env))
		out.Blank()

		expected := "nuke-" + d.env
		_, _ = fmt.Fprintf(os.Stdout, "Type %q to confirm: ", expected)

		scanner := bufio.NewScanner(os.Stdin)
		if !scanner.Scan() {
			return fmt.Errorf("no input received")
		}
		if strings.TrimSpace(scanner.Text()) != expected {
			out.Status("muted", "skip", "confirmation did not match; cancelled")
			return nil
		}
		out.Blank()

		if err := terraformInit(ctx, stack, root, d.env, d.creds); err != nil {
			return fmt.Errorf("terraform init: %w", err)
		}

		d.log.Info("running terraform destroy", "env", d.env)

		args := append([]string{"destroy", "-auto-approve"}, varFileArgs(stack, root, d.env)...)
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
			return fmt.Errorf("terraform destroy exited with code %d", code)
		}

		out.Blank()
		out.Status("ok", "ok", fmt.Sprintf("%s infrastructure destroyed", d.env))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(nukeCmd)
}
