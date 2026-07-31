describe("Aladin API", function()
  local AladinApi
  local original_search_target
  local saved_modules = {}
  local stub_modules

  setup(function()
    stub_modules = {
      ["hardcover_config"] = {
        aladin_ttb_key = "test-key",
      },
      ["socket.http"] = {},
      ["json"] = {},
      ["ltn12"] = {},
      ["socket.url"] = {
        escape = function(value) return value end,
      },
      ["socketutil"] = {},
      ["ui/network/manager"] = {},
      ["ui/trapper"] = {},
    }

    for name, stub in pairs(stub_modules) do
      saved_modules[name] = package.loaded[name]
      package.loaded[name] = stub
    end

    saved_modules["hardcover/lib/aladin_api"] = package.loaded["hardcover/lib/aladin_api"]
    package.loaded["hardcover/lib/aladin_api"] = nil
    AladinApi = require("hardcover/lib/aladin_api")
    original_search_target = AladinApi._searchTarget
  end)

  before_each(function()
    AladinApi._searchTarget = original_search_target
    AladinApi.settings = nil
    stub_modules["hardcover_config"].aladin_ttb_key = "test-key"
  end)

  teardown(function()
    for name, _ in pairs(stub_modules) do
      package.loaded[name] = saved_modules[name]
    end
    package.loaded["hardcover/lib/aladin_api"] = saved_modules["hardcover/lib/aladin_api"]
  end)

  it("searches ebooks before print books and removes duplicate ISBNs", function()
    local targets = {}

    function AladinApi:_searchTarget(query, target)
      table.insert(targets, { query = query, target = target })
      if target == "eBook" then
        return {
          { isbn_13 = "9788934972631", title = "만들어진 신" },
        }
      end

      return {
        { isbn_13 = "9788934972631", title = "만들어진 신" },
        { isbn_13 = "9788934926184", title = "만들어진 신" },
      }
    end

    local results = AladinApi:search("만들어진 신", "리처드 도킨스")

    assert.are.same({
      { query = "만들어진 신 리처드 도킨스", target = "eBook" },
      { query = "만들어진 신 리처드 도킨스", target = "Book" },
    }, targets)
    assert.are.same({
      { isbn_13 = "9788934972631", title = "만들어진 신" },
      { isbn_13 = "9788934926184", title = "만들어진 신" },
    }, results)
  end)

  it("reports a missing TTB key", function()
    stub_modules["hardcover_config"].aladin_ttb_key = ""

    local results, err = AladinApi:_searchTarget("만들어진 신", "Book")

    assert.is_nil(results)
    assert.are.equal("missing_key", err.aladin)
  end)

  it("prefers a TTB key saved in the plugin settings", function()
    AladinApi.settings = {
      readSetting = function() return "settings-key" end,
    }

    assert.are.equal("settings-key", AladinApi:getKey())
    assert.is_true(AladinApi:isConfigured())
  end)
end)
