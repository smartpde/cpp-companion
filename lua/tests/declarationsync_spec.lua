local declarationsync = require("cpp-companion.internal.declarationsync")
local tables = require("cpp-companion.internal.tables")

local function make_code_buf(code)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "cpp"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
  return buf
end

local function check_declarations(code, declarations)
  local buf = make_code_buf(code)
  local actual = declarationsync.get_declarations(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, declarations)
end

describe("declarationsync", function()
  describe("finds", function()
    it("declaration with simple type", function()
      check_declarations([[
int Func();
]],
        {
          "int Func()",
        })
    end)

    it("declaration with pointer type", function()
      check_declarations([[
int* Func();
]],
        {
          "int* Func()",
        })
    end)

    it("declaration with reference type", function()
      check_declarations([[
int& Func();
]],
        {
          "int& Func()",
        })
    end)

    it("declaration with template type", function()
      check_declarations([[
absl::StatusOr<int> Func();
]],
        {
          "absl::StatusOr<int> Func()",
        })
    end)

    it("declaration with const type", function()
      check_declarations([[
const Type Func();
]],
        {
          "const Type Func()",
        })
    end)

    it("declaration const func type", function()
      check_declarations([[
void Func() const;
]],
        {
          "void Func() const",
        })
    end)

    it("declaration with thread annotation", function()
      check_declarations([[
void Func() ABSL_GUARDED_BY(mutex_);
]],
        {
          "void Func()",
        })
    end)

    it("declaration with thread annotation and param", function()
      check_declarations([[
void Func(int a) ABSL_GUARDED_BY(mutex_);
]],
        {
          "void Func(int a)",
        })
    end)

    it("declaration with thread annotation return pointer", function()
      check_declarations([[
int* Func() ABSL_GUARDED_BY(mutex_);
]],
        {
          "int* Func()",
        })
    end)

    it("declaration with params", function()
      check_declarations([[
void Func(int a, std::string b);
]],
        {
          "void Func(int a, std::string b)",
        })
    end)

    it("declaration with params and default value", function()
      check_declarations([[
void Func(int a, std::string b = "b");
]],
        {
          [[void Func(int a, std::string b = "b")]],
        })
    end)

    it("declaration with multiline params", function()
      check_declarations([[
void Func(
  int a, std::string b);
]],
        {
          [[void Func(int a, std::string b)]],
        })
    end)

    it("declaration in namespace", function()
      check_declarations([[
namespace n1 {
namespace n2 {
  void Func();
}
}
]],
        {
          "n1::n2 void Func()",
        })
    end)

    it("declaration in class", function()
      check_declarations([[
namespace n1 {
class C1 {
class C2 {
 public:
  void Func();
};
};
}
]],
        {
          "n1 void C1::C2::Func()",
        })
    end)
  end)
end)
