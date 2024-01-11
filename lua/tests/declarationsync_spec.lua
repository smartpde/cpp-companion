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

local function check_definitions(code, definitions)
  local buf = make_code_buf(code)
  local actual = declarationsync.get_definitions(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, definitions)
end

describe("declarationsync", function()
  describe("finds declarations", function()
    it("with simple type", function()
      check_declarations([[
int Func();
]],
        {
          "int Func()",
        })
    end)

    it("with pointer type", function()
      check_declarations([[
int* Func();
]],
        {
          "int* Func()",
        })
    end)

    it("with double pointer type", function()
      check_declarations([[
int** Func();
]],
        {
          "int** Func()",
        })
    end)

    it("with reference type", function()
      check_declarations([[
int& Func();
]],
        {
          "int& Func()",
        })
    end)

    it("with template type", function()
      check_declarations([[
absl::StatusOr<int> Func();
]],
        {
          "absl::StatusOr<int> Func()",
        })
    end)

    it("with const type", function()
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

    it("with thread annotation", function()
      check_declarations([[
void Func() ABSL_GUARDED_BY(mutex_);
]],
        {
          "void Func()",
        })
    end)

    it("with thread annotation and param", function()
      check_declarations([[
void Func(int a) ABSL_GUARDED_BY(mutex_);
]],
        {
          "void Func(int a)",
        })
    end)

    it("with thread annotation return pointer", function()
      check_declarations([[
int* Func() ABSL_GUARDED_BY(mutex_);
]],
        {
          "int* Func()",
        })
    end)

    it("with params", function()
      check_declarations([[
void Func(int a, std::string b);
]],
        {
          "void Func(int a, std::string b)",
        })
    end)

    it("with params and default value", function()
      check_declarations([[
void Func(int a, std::string b = "b");
]],
        {
          [[void Func(int a, std::string b = "b")]],
        })
    end)

    it("with multiline params", function()
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

  describe("finds definitions", function()
    it("with simple type", function()
      check_definitions([[
int Func() {}
]],
        {
          "int Func()",
        })
    end)

    it("with parameters", function()
      check_definitions([[
int Func(int b) {}
]],
        {
          "int Func(int b)",
        })
    end)

    it("in namespace", function()
      check_definitions([[
namespace n {
  int Func() {}
}
]],
        {
          "n int Func()",
        })
    end)

    it("in class", function()
      check_definitions([[
class C {
  int Func() {}
};
]],
        {
          "int C::Func()",
        })
    end)
  end)

  it("skips non function declarations and definitions", function()
    check_declarations([[
int Func();
int a;
class C {
  int a = 0;
};
]],
      {
        "int Func()",
      })
  end)
end)
