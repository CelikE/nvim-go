# nvim-go

A comprehensive Go development plugin for NeoVim that enhances your Go development workflow with code generation, refactoring tools, and utilities following the [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md).

## Features

### Struct Operations
- **Generate Constructor** - Create `NewStructName()` with all fields mapped
- **Generate Builder Pattern** - Fluent builder for complex struct construction
- **Generate Functional Options** - `WithField()` pattern for optional configuration
- **Add/Remove Tags** - JSON, YAML, DB, and validation tags
- **Generate Getters/Setters** - Accessor methods with proper naming

### Interface Operations
- **Implement Interface** - Generate method stubs for any interface
- **Extract Interface** - Create interface from existing struct methods
- **Generate Mocks** - Basic mock implementation with call tracking

### Code Generation
- **Table-Driven Tests** - Uber-style test scaffolding with subtests
- **Benchmarks** - Performance test templates
- **Custom Error Types** - Error structs with `Error()` and `Unwrap()`
- **Enum String Methods** - `String()` for iota constants

### Utilities
- **Fill Struct Literal** - Populate with zero values
- **Toggle Receiver Type** - Switch between pointer/value receivers
- **Organize Imports** - Uber-style grouping (stdlib, external, internal)
- **Generate Documentation** - Go doc comments

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "CelikE/nvim-go",
  ft = "go",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    -- your configuration
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "CelikE/nvim-go",
  requires = { "nvim-treesitter/nvim-treesitter" },
  ft = "go",
  config = function()
    require("nvim-go").setup()
  end,
}
```

## Requirements

- NeoVim 0.8+
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with Go parser installed
- `gofmt` or `goimports` in PATH (for formatting)

## Configuration

```lua
require("nvim-go").setup({
  -- Keymaps configuration
  keymaps = {
    enabled = true,      -- Enable default keymaps
    prefix = "<leader>g", -- Keymap prefix
  },

  -- Constructor generation options
  constructor = {
    prefix = "New",      -- Constructor function prefix
    comment = true,      -- Add doc comment
  },

  -- Struct tag options
  tags = {
    json = {
      transform = "camelcase",  -- camelcase, snakecase, pascalcase, lispcase, keep
      options = {},             -- Additional tag options like "omitempty"
    },
    yaml = {
      transform = "camelcase",
      options = {},
    },
    db = {
      transform = "snakecase",
      options = {},
    },
    validate = {
      transform = "keep",
      options = {},
    },
  },

  -- Test generation options
  test = {
    template = "table",  -- table or simple
    parallel = true,     -- Add t.Parallel()
  },

  -- Style options
  style = {
    uber = true,  -- Follow Uber Go Style Guide
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:GoCodeAction` | Show available code actions at cursor |
| `:GoGenConstructor` | Generate constructor for struct |
| `:GoGenBuilder` | Generate builder pattern |
| `:GoAddJsonTags` | Add JSON tags to struct fields |
| `:GoAddYamlTags` | Add YAML tags to struct fields |
| `:GoAddDbTags` | Add DB tags to struct fields |
| `:GoAddValidateTags` | Add validation tags |
| `:GoAddAllTags` | Add all common tags |
| `:GoRemoveTags` | Remove all tags |
| `:GoGenGetters` | Generate getter methods |
| `:GoGenSetters` | Generate setter methods |
| `:GoGenGettersSetters` | Generate both |
| `:GoImplInterface` | Implement interface for struct |
| `:GoExtractInterface` | Extract interface from methods |
| `:GoGenTest` | Generate table-driven test |
| `:GoGenBenchmark` | Generate benchmark |
| `:GoGenMock` | Generate mock for interface |
| `:GoGenError` | Generate custom error type |
| `:GoGenEnum` | Generate String() for enum |
| `:GoFillStruct` | Fill struct literal with zero values |
| `:GoSplitStruct` | Toggle struct literal format |
| `:GoToggleReceiver` | Toggle pointer/value receiver |
| `:GoOrganizeImports` | Organize imports (Uber style) |
| `:GoGenDoc` | Generate documentation comment |

## Default Keymaps

When `keymaps.enabled = true`, these keymaps are set for Go files:

| Keymap | Command | Description |
|--------|---------|-------------|
| `<leader>ga` | GoCodeAction | Show code actions |
| `<leader>gc` | GoGenConstructor | Generate constructor |
| `<leader>gb` | GoGenBuilder | Generate builder |
| `<leader>gtj` | GoAddJsonTags | Add JSON tags |
| `<leader>gty` | GoAddYamlTags | Add YAML tags |
| `<leader>gtd` | GoAddDbTags | Add DB tags |
| `<leader>gtv` | GoAddValidateTags | Add validate tags |
| `<leader>gta` | GoAddAllTags | Add all tags |
| `<leader>gtr` | GoRemoveTags | Remove tags |
| `<leader>ggg` | GoGenGetters | Generate getters |
| `<leader>ggs` | GoGenSetters | Generate setters |
| `<leader>gga` | GoGenGettersSetters | Generate both |
| `<leader>gii` | GoImplInterface | Implement interface |
| `<leader>gie` | GoExtractInterface | Extract interface |
| `<leader>gtt` | GoGenTest | Generate test |
| `<leader>gtb` | GoGenBenchmark | Generate benchmark |
| `<leader>gtm` | GoGenMock | Generate mock |
| `<leader>ge` | GoGenError | Generate error type |
| `<leader>gn` | GoGenEnum | Generate enum String() |
| `<leader>gf` | GoFillStruct | Fill struct |
| `<leader>gr` | GoToggleReceiver | Toggle receiver |
| `<leader>go` | GoOrganizeImports | Organize imports |
| `<leader>gd` | GoGenDoc | Generate documentation |

## Examples

### Generate Constructor

Place cursor on a struct and run `:GoGenConstructor`:

```go
// Before
type User struct {
    ID        int64
    Name      string
    Email     string
    CreatedAt time.Time
}

// After - constructor is generated below the struct
// NewUser creates a new User instance.
func NewUser(id int64, name string, email string, createdAt time.Time) *User {
    return &User{
        ID:        id,
        Name:      name,
        Email:     email,
        CreatedAt: createdAt,
    }
}
```

### Add Tags

Place cursor on struct and run `:GoAddJsonTags`:

```go
// Before
type User struct {
    ID        int64
    FirstName string
    LastName  string
}

// After
type User struct {
    ID        int64  `json:"id"`
    FirstName string `json:"firstName"`
    LastName  string `json:"lastName"`
}
```

### Generate Table-Driven Test

Place cursor on a function and run `:GoGenTest`:

```go
func Add(a, b int) int {
    return a + b
}

// Generated test:
func TestAdd(t *testing.T) {
    t.Parallel()

    tests := []struct {
        name string
        a    int
        b    int
        want int
    }{
        {
            name: "success",
            a:    0,
            b:    0,
            want: 0,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()

            got := Add(tt.a, tt.b)

            if got != tt.want {
                t.Errorf("Add() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

### Implement Interface

Place cursor on a struct and run `:GoImplInterface`, then enter interface name:

```go
type UserService struct {
    db *sql.DB
}

// After implementing io.Reader:
// Ensure UserService implements io.Reader.
var _ io.Reader = (*UserService)(nil)

// Read implements io.Reader.
func (u *UserService) Read(p []byte) (n int, err error) {
    panic("not implemented")
}
```

### Organize Imports

Run `:GoOrganizeImports` to group imports per Uber style:

```go
// Before
import (
    "github.com/mycompany/myproject/internal/user"
    "fmt"
    "github.com/gin-gonic/gin"
    "context"
    "github.com/mycompany/myproject/internal/auth"
)

// After
import (
    "context"
    "fmt"

    "github.com/gin-gonic/gin"

    "github.com/mycompany/myproject/internal/auth"
    "github.com/mycompany/myproject/internal/user"
)
```

## Programmatic API

You can also use the plugin programmatically:

```lua
local nvim_go = require("nvim-go")

-- Generate constructor for struct at cursor
nvim_go.constructor.generate()

-- Add JSON tags
nvim_go.tags.add_json()

-- Implement interface
nvim_go.interface.implement()
```

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the [Uber Go Style Guide](https://github.com/uber-go/guide)
- Built with [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
