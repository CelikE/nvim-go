// Package cmd implements the CLI commands for nvim-go.
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
)

// Execute runs the CLI application.
func Execute() error {
	if len(os.Args) < 2 {
		return fmt.Errorf("usage: nvim-go <command> [args]")
	}

	command := os.Args[1]

	switch command {
	case "parse":
		return runParse()
	case "struct":
		return runStruct()
	case "interface":
		return runInterface()
	case "imports":
		return runImports()
	case "version":
		fmt.Println("nvim-go v1.0.0")
		return nil
	case "help":
		printHelp()
		return nil
	default:
		return fmt.Errorf("unknown command: %s", command)
	}
}

func printHelp() {
	fmt.Println(`nvim-go - Go development assistant for NeoVim

Commands:
  parse      Parse Go file and output AST info as JSON
  struct     Get struct information at position
  interface  Get interface information
  imports    Analyze and organize imports
  version    Show version
  help       Show this help

Usage:
  nvim-go parse <file> [line] [col]
  nvim-go struct <file> <line>
  nvim-go interface <file> <name>
  nvim-go imports <file>`)
}

// outputJSON writes data as JSON to stdout.
func outputJSON(data any) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(data)
}
