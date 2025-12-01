// Package main provides the nvim-go CLI tool.
// This tool assists the NeoVim plugin with complex Go code analysis
// that benefits from native Go parsing capabilities.
package main

import (
	"fmt"
	"os"

	"github.com/CelikE/nvim-go/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
