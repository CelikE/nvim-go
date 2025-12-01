package cmd

import (
	"fmt"
	"os"

	"github.com/CelikE/nvim-go/internal/parser"
)

func runParse() error {
	if len(os.Args) < 3 {
		return fmt.Errorf("usage: nvim-go parse <file>")
	}

	filename := os.Args[2]

	info, err := parser.ParseFile(filename)
	if err != nil {
		return fmt.Errorf("parsing file: %w", err)
	}

	return outputJSON(info)
}
