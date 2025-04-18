local table_util = require("hardcover/lib/table_util")
describe("table_util", function()
  describe("dig", function()
    it("fetches nested table values", function()
      local t = {
        a = {
          b = {
            10,
            20,
            30,
          }
        }
      }
      assert.are.equal(30, table_util.dig(t, "a", "b", 3))
    end)

    it("returns nil for missing values", function()
      local t = {
        a = {
          b = {
            10,
            20,
            30,
          }
        }
      }
      assert.is_nil(table_util.dig(t, "a", "c", 3))
    end)
  end)

  describe("map", function()
    it("returns table containing callback result", function()
      local input = { 1, 2, 3, 4 }
      local result = table_util.map(input, function(el) return el * 2 end)

      assert.are.same(result, { 2, 4, 6, 8 })
    end)

    it("passes table index to map callbacks", function()
      local input = { "a", "b", "c" }

      local result = table_util.map(input, function(el, index) return index end)

      assert.are.same(result, { 1, 2, 3 })
    end)
  end)

  describe("contains", function()
    it("compares object equality", function()
      local subtable = { 1, 2, 3 }
      local t = { "a", "b", subtable }

      assert.is_true(table_util.contains(t, "b"))
      assert.is_true(table_util.contains(t, subtable))
      assert.is_false(table_util.contains(t, "c"))
      assert.is_false(table_util.contains(t, { 1, 2, 3 }))
    end)
  end)

  describe("filter", function()
    it("selects table elements by callback", function()
      local input = { 1, 2, 3, 4, 5, 6 }
      local result = table_util.filter(input, function(v, k) return v % 2 == 0 end)
      assert.are.same(result, { 2, 4, 6 })
    end)

    it("selects table elements by index", function()
      local input = { 10, 20, 30, 40, 50, 60 }
      local result = table_util.filter(input, function(v, k) return k % 2 == 0 end)
      assert.are.same(result, { 20, 40, 60 })
    end)
  end)

  describe("slice", function()
    it("returns limited result", function()
      local input = { 1, 2, 3, 4, 5, 6 }
      local result = table_util.slice(input, 4)

      assert.are.same(result, { 4, 5, 6 })
    end)

    it("returns offset result", function()
      local input = { 1, 2, 3, 4, 5, 6 }
      local result = table_util.slice(input, 1, 3)

      assert.are.same(result, { 1, 2, 3 })
    end)

    it("limits end to table length", function()
      local input = { 1, 2, 3 }
      local result = table_util.slice(input, 4)

      assert.are.same(result, {})
    end)

    it("returns midsection of input", function()
      local input = { 1, 2, 3, 4, 5, 6 }
      local result = table_util.slice(input, 3, 4)

      assert.are.same(result, { 3, 4 })
    end)
  end)

  describe("binSearch", function()
    it("returns nil for an empty table", function()
      assert.is_nil(table_util.binSearch({}, 5))
    end)

    it("returns first index over search value for 1 element table", function()
      local t = { 5 }
      assert.is_equal(1, table_util.binSearch(t, 2))
    end)

    it("returns first index over search value for 2 element table", function()
      local t = { 5, 10 }
      assert.is_equal(2, table_util.binSearch(t, 7))
      assert.is_equal(1, table_util.binSearch(t, 2))
    end)

    it("returns nil if all values are below the search value", function()
      local t = { 5, 10, 15 }
      assert.is_nil(table_util.binSearch(t, 20))
    end)
  end)
end)
