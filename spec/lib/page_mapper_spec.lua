local PageMapper = require("lib/page_mapper")

describe("PageMapper", function()
  describe("cachePageMap", function()
    local ui = function(page_map)
      return {
        document = {
          getPageMap = function()
            return page_map
          end
        }
      }
    end

    it("does not translate page map when document has no page map", function()
      local map = nil
      local state = {}

      local page_map = PageMapper:new {
        state = state,
        ui = ui(map)
      }

      page_map:cachePageMap()
      assert.is_nil(state.page_map)
    end)

    it("create a table of raw page numbers to canonical book page integers", function()
      local map = {
        {
          page = 1,
          label = "i",
        },
        {
          page = 2,
          label = "ii",
        },
        {
          page = 3,
          label = "iii"
        }
      }

      local state = {}

      local page_map = PageMapper:new {
        state = state,
        ui = ui(map)
      }
      page_map:cachePageMap()
      local expected = {
        [1] = 1,
        [2] = 2,
        [3] = 3
      }
      assert.are.same(expected, state.page_map)
    end)

    it("fills gaps in raw page numbers", function()
      local map = {
        {
          page = 1,
          label = "i",
        },
        {
          page = 3,
          label = "ii",
        },
        {
          page = 5,
          label = "iii"
        }
      }

      local state = {}

      local page_map = PageMapper:new {
        state = state,
        ui = ui(map)
      }
      page_map:cachePageMap()
      local expected = {
        [1] = 1,
        [2] = 1,
        [3] = 2,
        [4] = 2,
        [5] = 3
      }
      assert.are.same(expected, state.page_map)
    end)

    it("maps multiple pages to canonical page integers", function()
      local map = {
        {
          page = 1,
          label = "i",
        },
        {
          page = 2,
          label = "i",
        },
        {
          page = 3,
          label = "i"
        }
      }

      local state = {}

      local page_map = PageMapper:new {
        state = state,
        ui = ui(map)
      }
      page_map:cachePageMap()
      local expected = {
        [1] = 1,
        [2] = 1,
        [3] = 1,
      }
      assert.are.same(expected, state.page_map)
    end)
  end)

  describe("getMappedPage", function()
    it("returns the page mapped page if available", function()
      local page_map = PageMapper:new {
        state = {
          page_map = {
            [1] = 99
          }
        }
      }

      assert.are.equal(page_map:getMappedPage(1, 100, 50), 99)
    end)

    it("translates local pages to canonical pages", function()
      local page_map = PageMapper:new {
        state = {}
      }
      local current_page = 1
      local document_pages = 2
      local canonical_pages = 20

      local expected = 10

      assert.are.equal(expected, page_map:getMappedPage(current_page, document_pages, canonical_pages))
    end)
  end)

  describe("getMappedPercent", function()
    it("returns the mapped page as a percentage of the canonical total pages", function()
      local page_map = PageMapper:new {
        state = {
          page_map = {
            [10] = 50
          }
        }
      }

      assert.are.equal(0.5, page_map:getMappedPagePercent(10, 10000, 100))
    end)

    it("returns the completion percentage if no map is available", function()
      local page_map = PageMapper:new { state = {} }
      assert.are.equal(0.5, page_map:getMappedPagePercent(10, 20, 10000))
    end)
  end)

  describe("getRemotePagePercent", function()
    it("returns the percent of the equivalent floored remote page", function()
      local page_map = PageMapper:new { state = {} }

      local percent, page = page_map:getRemotePagePercent(10, 20, 29)

      assert.are.equal(14 / 29, percent)
      assert.are.equal(14, page)
    end)

    it("returns a simple percentage if remote page is unavailable", function()
      local page_map = PageMapper:new { state = {} }

      local percent, page = page_map:getRemotePagePercent(10, 20)

      assert.are.equal(0.5, percent)
      assert.are.equal(10, page)
    end)
  end)
end)
