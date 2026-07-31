describe("Hardcover API ISBN batch lookup", function()
  local Api
  local original_query
  local saved_modules = {}
  local stub_modules

  setup(function()
    stub_modules = {
      ["hardcover_config"] = { token = "test-token" },
      ["logger"] = {},
      ["socket.http"] = {},
      ["ltn12"] = {},
      ["json"] = {},
      ["ffi/util"] = {
        template = function(value) return value end,
      },
      ["ui/trapper"] = {},
      ["ui/network/manager"] = {},
      ["socketutil"] = {},
      ["hardcover_version"] = { 0, 5, 0 },
    }

    for name, stub in pairs(stub_modules) do
      saved_modules[name] = package.loaded[name]
      package.loaded[name] = stub
    end

    saved_modules["hardcover/lib/hardcover_api"] = package.loaded["hardcover/lib/hardcover_api"]
    package.loaded["hardcover/lib/hardcover_api"] = nil
    Api = require("hardcover/lib/hardcover_api")
    original_query = Api.query
  end)

  before_each(function()
    Api.query = original_query
  end)

  teardown(function()
    for name, _ in pairs(stub_modules) do
      package.loaded[name] = saved_modules[name]
    end
    package.loaded["hardcover/lib/hardcover_api"] = saved_modules["hardcover/lib/hardcover_api"]
  end)

  it("returns exact editions in Aladin ISBN order", function()
    function Api:query(_, parameters)
      assert.are.same({
        "9788934972631",
        "893492618X",
      }, parameters.isbns)
      assert.are.equal(7, parameters.userId)

      return {
        editions = {
          {
            id = 20,
            isbn_10 = "893492618X",
            isbn_13 = "9788934926184",
            title = "만들어진 신",
            reading_format_id = 1,
            book = { book_id = 382874 },
          },
          {
            id = 10,
            isbn_10 = "8934972637",
            isbn_13 = "9788934972631",
            title = "만들어진 신",
            reading_format_id = 4,
            book = { book_id = 382874 },
          },
        },
      }
    end

    local results = Api:findBooksByIsbns({
      "9788934972631",
      "893492618X",
    }, 7)

    assert.are.equal(2, #results)
    assert.are.equal(10, results[1].edition_id)
    assert.are.equal("9788934972631", results[1].isbn_13)
    assert.are.equal(20, results[2].edition_id)
    assert.are.equal("893492618X", results[2].isbn_10)
  end)
end)
