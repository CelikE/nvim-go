package cmd

import (
	"fmt"
	"os"
	"strconv"

	"github.com/CelikE/nvim-go/internal/parser"
)

func runStruct() error {
	if len(os.Args) < 4 {
		return fmt.Errorf("usage: nvim-go struct <file> <line>")
	}

	filename := os.Args[2]
	line, err := strconv.Atoi(os.Args[3])
	if err != nil {
		return fmt.Errorf("invalid line number: %w", err)
	}

	info, err := parser.ParseFile(filename)
	if err != nil {
		return fmt.Errorf("parsing file: %w", err)
	}

	// Find struct at line
	for _, s := range info.Structs {
		if line >= s.StartLine && line <= s.EndLine {
			return outputJSON(s)
		}
	}

	return fmt.Errorf("no struct found at line %d", line)
}
