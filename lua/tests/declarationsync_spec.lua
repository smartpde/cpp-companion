local declarationsync = require("cpp-companion.internal.declarationsync")
local tables = require("cpp-companion.internal.tables")
local strings = require("cpp-companion.internal.strings")

local function make_code_buf(code_lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "cpp"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, code_lines)
  return buf
end

local function check_declarations(code, declarations)
  local buf = make_code_buf(vim.split(code, "\n"))
  local actual = declarationsync.get_declarations(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, declarations)
end

local function check_definitions(code, definitions)
  local buf = make_code_buf(vim.split(code, "\n"))
  local actual = declarationsync.get_definitions(buf)
  local actual_funcs = tables.map(actual, function(d)
    return declarationsync.func_display(d)
  end)
  assert.are.same(actual_funcs, definitions)
end

local function trim_lines(lines)
  for i, l in ipairs(lines) do
    lines[i] = strings.trim(l)
  end
  return table.concat(lines, "\n")
end

local function trim_text(text)
  local lines = vim.split(text, "\n")
  return trim_lines(lines)
end

local function check_sync(code, expected_code)
  local lines = vim.split(code, "\n")
  local row, col
  for i, l in ipairs(lines) do
    local c = string.find(l, "%^")
    if c then
      row = i
      col = c
      lines[i] = string.gsub(l, "%^", "")
      break
    end
  end
  local buf = make_code_buf(lines)
  local win = vim.api.nvim_open_win(buf, false, { height = 100, width = 100, relative = "editor", row = 1, col = 1 })
  vim.api.nvim_win_set_cursor(win, { row, col - 1 })
  declarationsync.sync_declaration_and_definition(win)
  local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert.are.same(trim_lines(new_lines), trim_text(expected_code))
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
class C {
  void Func() ABSL_GUARDED_BY(mutex_);
};
]],
        {
          "void C::Func()",
        })
    end)

    it("with thread annotation and param", function()
      check_declarations([[
class C {
  void Func(int a) ABSL_GUARDED_BY(mutex_);
};
]],
        {
          "void C::Func(int a)",
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

    it("declaration in anonymouse namespace", function()
      check_declarations([[
namespace n1 {
namespace {
  void Func();
}
}
]],
        {
          "n1:: void Func()",
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

    it("static declaration in class", function()
      check_declarations([[
class C {
  static void Func();
}
]],
        {
          "static void C::Func()",
        })
    end)

    it("struct inside class", function()
      check_declarations([[
class C {
  struct S {
    void Func();
  };
};
]],
        {
          "void C::S::Func()",
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

  describe("sync", function()
    it("updates declaration", function()
      check_sync([[
  void func(int a);
  void func(double d) {
    ^
  }
]], [[
  void func(double d);
  void func(double d) {

  }
]])
    end)

    it("updates definition", function()
      check_sync([[
  void func(int a^);
  void func(double d) {
  }
]], [[
  void func(int a);
  void func(int a) {
  }
]])
    end)

    it("updates definition without default param values", function()
      check_sync([[
  void func(int a, int b = 2, int c = {}, ind d = func(), int* e = nullptr^);
  void func(double d) {
  }
]], [[
  void func(int a, int b = 2, int c = {}, ind d = func(), int* e = nullptr);
  void func(int a, int b, int c, ind d, int * e) {
  }
]])
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

  it("skips template variable guarded by mutex", function()
    check_declarations([[
class C {
  std::optional<O> field_ ABSL_GUARDED_BY(mutex);
};
]],
      {})
  end)
end)
