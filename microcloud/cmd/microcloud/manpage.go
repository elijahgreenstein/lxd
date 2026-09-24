package main

import (
	"github.com/spf13/cobra"
	"github.com/spf13/cobra/doc"

	"github.com/canonical/lxd/shared"
	cli "github.com/canonical/lxd/shared/cmd"
)

type cmdManpage struct {
	common *CmdControl

	flagFormat string
}

func (c *cmdManpage) command() *cobra.Command {
	cmd := &cobra.Command{}
	cmd.Use = "manpage <target>"
	cmd.Short = "Generate manpages for all commands"
	cmd.Long = cli.FormatSection("Description", `Generate manpages for all commands`)
	cmd.Hidden = true
	cmd.Args = cobra.ExactArgs(1)
	cmd.Flags().StringVarP(&c.flagFormat, "format", "f", "man", cli.FormatStringFlagLabel("Format (man|md|rest|yaml)"))

	cmd.RunE = c.run

	return cmd
}

func (c *cmdManpage) run(cmd *cobra.Command, args []string) error {
	// If asked to do all commands, mark them all visible.
	for _, c := range c.common.cmd.Commands() {
		if c.Name() == "completion" {
			continue
		}

		c.Hidden = false
	}

	// Generate the documentation.
	var err error
	switch c.flagFormat {
	case "man":
		header := &doc.GenManHeader{
			Title:   "MicroCloud - Command line client",
			Section: "1",
		}

		opts := doc.GenManTreeOptions{
			Header:           header,
			Path:             shared.HostPathFollow(args[0]),
			CommandSeparator: ".",
		}

		err = doc.GenManTreeFromOpts(c.common.cmd, opts)

	case "md":
		err = doc.GenMarkdownTree(c.common.cmd, shared.HostPathFollow(args[0]))

	case "rest":
		err = doc.GenReSTTree(c.common.cmd, shared.HostPathFollow(args[0]))

	case "yaml":
		err = doc.GenYamlTree(c.common.cmd, shared.HostPathFollow(args[0]))
	}

	return err
}

