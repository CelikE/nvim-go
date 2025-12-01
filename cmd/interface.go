package cmd

import (
	"fmt"
	"os"

	"github.com/CelikE/nvim-go/internal/parser"
)

func runInterface() error {
	if len(os.Args) < 4 {
		return fmt.Errorf("usage: nvim-go interface <file> <name>")
	}

	filename := os.Args[2]
	name := os.Args[3]

	info, err := parser.ParseFile(filename)
	if err != nil {
		return fmt.Errorf("parsing file: %w", err)
	}

	// Find interface by name
	for _, iface := range info.Interfaces {
		if iface.Name == name {
			return outputJSON(iface)
		}
	}

	return fmt.Errorf("interface %q not found", name)
}
