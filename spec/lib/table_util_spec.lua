local table_util = require("lib/table_util")
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
end)
