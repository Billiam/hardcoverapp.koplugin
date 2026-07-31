describe("Hardcover metadata search", function()
  local Api
  local Hardcover
  local saved_modules = {}
  local stub_modules

  setup(function()
    Api = {}
    stub_modules = {
      ["gettext"] = function(value) return value end,
      ["logger"] = {},
      ["util"] = {},
      ["ui/uimanager"] = {},
      ["ui/widget/notification"] = { new = function(_, value) return value end },
      ["ui/widget/infomessage"] = { new = function(_, value) return value end },
      ["hardcover/lib/hardcover_api"] = Api,
      ["hardcover/lib/user"] = { getId = function() return 1 end },
    }

    for name, stub in pairs(stub_modules) do
      saved_modules[name] = package.loaded[name]
      package.loaded[name] = stub
    end

    saved_modules["hardcover/lib/hardcover"] = package.loaded["hardcover/lib/hardcover"]
    package.loaded["hardcover/lib/hardcover"] = nil
    Hardcover = require("hardcover/lib/hardcover")
  end)

  teardown(function()
    for name, _ in pairs(stub_modules) do
      package.loaded[name] = saved_modules[name]
    end
    package.loaded["hardcover/lib/hardcover"] = saved_modules["hardcover/lib/hardcover"]
  end)

  it("uses the original Korean metadata first when it returns a good match", function()
    local calls = {}
    local expected = {
      title = "소년이 온다",
      contributions = { author = "한강" },
    }

    function Api:search(title, author)
      table.insert(calls, { title = title, author = author })
      return { expected }
    end

    local hardcover = Hardcover:new {}
    local results = hardcover:findBooksByMetadata("소년이 온다: 한강 장편소설", "한강 지음", 1)

    assert.are.same({ expected }, results)
    assert.are.same({
      { title = "소년이 온다: 한강 장편소설", author = "한강 지음" },
    }, calls)
  end)

  it("falls back to normalized Korean metadata after unrelated results", function()
    local calls = {}
    local expected = {
      title = "소년이 온다",
      contributions = { author = "한강" },
    }

    function Api:search(title, author)
      table.insert(calls, { title = title, author = author })
      if #calls == 1 then
        return {
          {
            title = "Human Acts",
            contributions = { author = "Han Kang" },
          },
        }
      end
      return { expected }
    end

    local hardcover = Hardcover:new {}
    local results = hardcover:findBooksByMetadata("소년이 온다: 한강 장편소설", "한강 지음", 1)

    assert.are.same({ expected }, results)
    assert.are.same({
      { title = "소년이 온다: 한강 장편소설", author = "한강 지음" },
      { title = "소년이 온다", author = "한강" },
    }, calls)
  end)

  it("retries normalized Korean metadata after an original-query error", function()
    local calls = {}
    local original_error = { errors = { { message = "search failed" } } }
    local expected = {
      title = "소년이 온다",
      contributions = { author = "한강" },
    }

    function Api:search(title, author)
      table.insert(calls, { title = title, author = author })
      if #calls == 1 then
        return nil, original_error
      end
      return { expected }
    end

    local hardcover = Hardcover:new {}
    local results, err = hardcover:findBooksByMetadata("소년이 온다: 한강 장편소설", "한강 지음", 1)

    assert.is_nil(err)
    assert.are.same({ expected }, results)
    assert.are.same({
      { title = "소년이 온다: 한강 장편소설", author = "한강 지음" },
      { title = "소년이 온다", author = "한강" },
    }, calls)
  end)

  it("retries a Korean title without the romanized author when indexed search misses", function()
    local calls = {}
    local expected = {
      title = "작별 하지 않는다",
      contributions = { author = "Han Kang" },
    }

    function Api:search(title, author)
      table.insert(calls, { title = title, author = author })
      if author == nil then
        return { expected }
      end
      return {}
    end

    local hardcover = Hardcover:new {}
    local results = hardcover:findBooksByMetadata(
      "작별하지 않는다 (장편소설)",
      "한강 저",
      1
    )

    assert.are.same({ expected }, results)
    assert.are.same({
      { title = "작별하지 않는다 (장편소설)", author = "한강 저" },
      { title = "작별하지 않는다", author = "한강" },
      { title = "작별하지 않는다", author = nil },
    }, calls)
  end)

  it("keeps the existing non-Korean findBooks path", function()
    local expected = {
      title = "The Hobbit",
      contributions = { author = "J. R. R. Tolkien" },
    }

    function Api:findBooks(title, author, user_id)
      assert.are.equal("The Hobbit: There and Back Again", title)
      assert.are.equal("J. R. R. Tolkien", author)
      assert.are.equal(7, user_id)
      return { expected }
    end

    function Api:search()
      error("non-Korean metadata should not use the new search path")
    end

    local hardcover = Hardcover:new {}
    local results, err, metadata = hardcover:findBooksByMetadata(
      "The Hobbit: There and Back Again",
      "J. R. R. Tolkien",
      7
    )

    assert.is_nil(err)
    assert.is_false(metadata.is_korean)
    assert.are.same({ expected }, results)
  end)
end)
