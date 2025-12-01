// Package parser provides Go source code parsing utilities.
package parser

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
)

// FileInfo contains parsed information about a Go source file.
type FileInfo struct {
	Package    string       `json:"package"`
	Imports    []ImportInfo `json:"imports"`
	Structs    []StructInfo `json:"structs"`
	Interfaces []IfaceInfo  `json:"interfaces"`
	Functions  []FuncInfo   `json:"functions"`
}

// ImportInfo represents an import declaration.
type ImportInfo struct {
	Path      string `json:"path"`
	Alias     string `json:"alias,omitempty"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
}

// StructInfo represents a struct type declaration.
type StructInfo struct {
	Name      string      `json:"name"`
	Fields    []FieldInfo `json:"fields"`
	StartLine int         `json:"start_line"`
	EndLine   int         `json:"end_line"`
}

// FieldInfo represents a struct field.
type FieldInfo struct {
	Names    []string          `json:"names"`
	Type     string            `json:"type"`
	Tag      string            `json:"tag,omitempty"`
	Tags     map[string]string `json:"tags,omitempty"`
	Embedded bool              `json:"embedded,omitempty"`
}

// IfaceInfo represents an interface type declaration.
type IfaceInfo struct {
	Name      string       `json:"name"`
	Methods   []MethodInfo `json:"methods"`
	StartLine int          `json:"start_line"`
	EndLine   int          `json:"end_line"`
}

// MethodInfo represents a method in an interface or struct.
type MethodInfo struct {
	Name       string      `json:"name"`
	Params     []ParamInfo `json:"params"`
	Results    []ParamInfo `json:"results,omitempty"`
	IsExported bool        `json:"is_exported"`
}

// ParamInfo represents a function parameter or result.
type ParamInfo struct {
	Names []string `json:"names,omitempty"`
	Type  string   `json:"type"`
}

// FuncInfo represents a function or method declaration.
type FuncInfo struct {
	Name      string      `json:"name"`
	Receiver  *ParamInfo  `json:"receiver,omitempty"`
	Params    []ParamInfo `json:"params"`
	Results   []ParamInfo `json:"results,omitempty"`
	StartLine int         `json:"start_line"`
	EndLine   int         `json:"end_line"`
}

// ParseFile parses a Go source file and returns structured information.
func ParseFile(filename string) (*FileInfo, error) {
	fset := token.NewFileSet()

	file, err := parser.ParseFile(fset, filename, nil, parser.ParseComments)
	if err != nil {
		return nil, err
	}

	info := &FileInfo{
		Package:    file.Name.Name,
		Imports:    make([]ImportInfo, 0),
		Structs:    make([]StructInfo, 0),
		Interfaces: make([]IfaceInfo, 0),
		Functions:  make([]FuncInfo, 0),
	}

	// Parse imports
	for _, imp := range file.Imports {
		importInfo := ImportInfo{
			Path:      strings.Trim(imp.Path.Value, `"`),
			StartLine: fset.Position(imp.Pos()).Line,
			EndLine:   fset.Position(imp.End()).Line,
		}
		if imp.Name != nil {
			importInfo.Alias = imp.Name.Name
		}
		info.Imports = append(info.Imports, importInfo)
	}

	// Walk AST for declarations
	ast.Inspect(file, func(n ast.Node) bool {
		switch decl := n.(type) {
		case *ast.GenDecl:
			if decl.Tok == token.TYPE {
				for _, spec := range decl.Specs {
					typeSpec, ok := spec.(*ast.TypeSpec)
					if !ok {
						continue
					}

					switch t := typeSpec.Type.(type) {
					case *ast.StructType:
						info.Structs = append(info.Structs, parseStruct(fset, typeSpec.Name.Name, t, decl))
					case *ast.InterfaceType:
						info.Interfaces = append(info.Interfaces, parseInterface(fset, typeSpec.Name.Name, t, decl))
					}
				}
			}
		case *ast.FuncDecl:
			info.Functions = append(info.Functions, parseFunc(fset, decl))
		}
		return true
	})

	return info, nil
}

func parseStruct(fset *token.FileSet, name string, st *ast.StructType, decl *ast.GenDecl) StructInfo {
	info := StructInfo{
		Name:      name,
		Fields:    make([]FieldInfo, 0),
		StartLine: fset.Position(decl.Pos()).Line,
		EndLine:   fset.Position(decl.End()).Line,
	}

	if st.Fields != nil {
		for _, field := range st.Fields.List {
			fieldInfo := FieldInfo{
				Names: make([]string, 0),
				Type:  typeToString(field.Type),
				Tags:  make(map[string]string),
			}

			for _, name := range field.Names {
				fieldInfo.Names = append(fieldInfo.Names, name.Name)
			}

			if len(fieldInfo.Names) == 0 {
				fieldInfo.Embedded = true
			}

			if field.Tag != nil {
				fieldInfo.Tag = strings.Trim(field.Tag.Value, "`")
				fieldInfo.Tags = parseStructTag(fieldInfo.Tag)
			}

			info.Fields = append(info.Fields, fieldInfo)
		}
	}

	return info
}

func parseInterface(fset *token.FileSet, name string, it *ast.InterfaceType, decl *ast.GenDecl) IfaceInfo {
	info := IfaceInfo{
		Name:      name,
		Methods:   make([]MethodInfo, 0),
		StartLine: fset.Position(decl.Pos()).Line,
		EndLine:   fset.Position(decl.End()).Line,
	}

	if it.Methods != nil {
		for _, method := range it.Methods.List {
			if len(method.Names) == 0 {
				continue // Embedded interface
			}

			funcType, ok := method.Type.(*ast.FuncType)
			if !ok {
				continue
			}

			methodInfo := MethodInfo{
				Name:       method.Names[0].Name,
				IsExported: ast.IsExported(method.Names[0].Name),
				Params:     parseFieldList(funcType.Params),
				Results:    parseFieldList(funcType.Results),
			}

			info.Methods = append(info.Methods, methodInfo)
		}
	}

	return info
}

func parseFunc(fset *token.FileSet, decl *ast.FuncDecl) FuncInfo {
	info := FuncInfo{
		Name:      decl.Name.Name,
		Params:    parseFieldList(decl.Type.Params),
		Results:   parseFieldList(decl.Type.Results),
		StartLine: fset.Position(decl.Pos()).Line,
		EndLine:   fset.Position(decl.End()).Line,
	}

	if decl.Recv != nil && len(decl.Recv.List) > 0 {
		recv := decl.Recv.List[0]
		recvInfo := ParamInfo{
			Type:  typeToString(recv.Type),
			Names: make([]string, 0),
		}
		for _, name := range recv.Names {
			recvInfo.Names = append(recvInfo.Names, name.Name)
		}
		info.Receiver = &recvInfo
	}

	return info
}

func parseFieldList(fl *ast.FieldList) []ParamInfo {
	if fl == nil {
		return nil
	}

	params := make([]ParamInfo, 0)

	for _, field := range fl.List {
		param := ParamInfo{
			Type:  typeToString(field.Type),
			Names: make([]string, 0),
		}

		for _, name := range field.Names {
			param.Names = append(param.Names, name.Name)
		}

		params = append(params, param)
	}

	return params
}

func typeToString(expr ast.Expr) string {
	switch t := expr.(type) {
	case *ast.Ident:
		return t.Name
	case *ast.SelectorExpr:
		return typeToString(t.X) + "." + t.Sel.Name
	case *ast.StarExpr:
		return "*" + typeToString(t.X)
	case *ast.ArrayType:
		if t.Len == nil {
			return "[]" + typeToString(t.Elt)
		}
		return "[...]" + typeToString(t.Elt)
	case *ast.MapType:
		return "map[" + typeToString(t.Key) + "]" + typeToString(t.Value)
	case *ast.ChanType:
		switch t.Dir {
		case ast.SEND:
			return "chan<- " + typeToString(t.Value)
		case ast.RECV:
			return "<-chan " + typeToString(t.Value)
		default:
			return "chan " + typeToString(t.Value)
		}
	case *ast.FuncType:
		return "func(...)"
	case *ast.InterfaceType:
		return "interface{}"
	case *ast.Ellipsis:
		return "..." + typeToString(t.Elt)
	default:
		return "unknown"
	}
}

func parseStructTag(tag string) map[string]string {
	result := make(map[string]string)

	for tag != "" {
		// Skip whitespace
		i := 0
		for i < len(tag) && tag[i] == ' ' {
			i++
		}
		tag = tag[i:]
		if tag == "" {
			break
		}

		// Find key
		i = 0
		for i < len(tag) && tag[i] != ':' && tag[i] != '"' && tag[i] != ' ' {
			i++
		}
		if i >= len(tag) {
			break
		}
		key := tag[:i]
		tag = tag[i:]

		if tag == "" || tag[0] != ':' {
			break
		}
		tag = tag[1:]

		if tag == "" || tag[0] != '"' {
			break
		}
		tag = tag[1:]

		// Find value end
		i = 0
		for i < len(tag) && tag[i] != '"' {
			if tag[i] == '\\' && i+1 < len(tag) {
				i++
			}
			i++
		}
		if i >= len(tag) {
			break
		}

		value := tag[:i]
		tag = tag[i+1:]

		result[key] = value
	}

	return result
}
