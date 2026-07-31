describe("Hardcover metadata search", function()
  local AladinApi
  local Api
  local Hardcover
  local saved_modules = {}
  local stub_modules

  setup(function()
    AladinApi = {
      configured = false,
      isConfigured = function(self) return self.configured end,
    }
    Api = {}
    stub_modules = {
      ["gettext"] = function(value) return value end,
      ["logger"] = {},
      ["util"] = {},
      ["ui/uimanager"] = {},
      ["ui/widget/notification"] = { new = function(_, value) return value end },
      ["ui/widget/infomessage"] = { new = function(_, value) return value end },
      ["hardcover/lib/aladin_api"] = AladinApi,
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

  before_each(function()
    AladinApi.configured = false
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

  it("uses Aladin only for Korean discovery when a TTB key is configured", function()
    local aladin_calls = {}
    local isbn_calls = {}
    local expected = {
      book_id = 382874,
      edition_id = 33126542,
      isbn_13 = "9788934972631",
      title = "만들어진 신",
      contributions = { author = "Richard Dawkins" },
    }

    AladinApi.configured = true
    function AladinApi:search(title, author)
      table.insert(aladin_calls, { title = title, author = author })
      return {
        {
          title = "만들어진 신 - 신은 과연 인간을 창조했는가?",
          isbn_10 = nil,
          isbn_13 = "9788934972631",
          link = "https://www.aladin.co.kr/example",
        },
      }
    end

    function Api:findBooksByIsbns(isbns, user_id)
      table.insert(isbn_calls, { isbns = isbns, user_id = user_id })
      return { expected }
    end

    function Api:search()
      error("Korean discovery should not search Hardcover when Aladin is configured")
    end

    local hardcover = Hardcover:new {}
    local results, err, metadata = hardcover:findBooksByMetadata(
      "만들어진 신: 신은 과연 인간을 창조했는가?",
      "리처드 도킨스 지음, 이한음 옮김",
      7
    )

    assert.is_nil(err)
    assert.are.same({ expected }, results)
    assert.are.same({
      { title = "만들어진 신", author = "리처드 도킨스" },
    }, aladin_calls)
    assert.are.same({
      { isbns = { "9788934972631" }, user_id = 7 },
    }, isbn_calls)
    assert.is_true(results[1].aladin_source)
    assert.are.equal("https://www.aladin.co.kr/example", results[1].aladin_link)
    assert.are.equal("만들어진 신 - 신은 과연 인간을 창조했는가?", results[1].title)
    assert.are.equal("만들어진 신", results[1].hardcover_title)
    assert.are.equal(1, metadata.aladin_result_count)
    assert.are.equal(1, metadata.aladin_linked_count)
  end)

  it("retries an automatic Aladin search without the author when no edition resolves", function()
    local aladin_calls = {}
    local isbn_calls = {}

    AladinApi.configured = true
    function AladinApi:search(title, author)
      table.insert(aladin_calls, { title = title, author = author })
      if author then
        return {
          { title = "Unrelated", isbn_13 = "9780306406157" },
        }
      end
      return {
        {
          title = "이기적 유전자 - 2010년 전면개정판",
          isbn_13 = "9788932471631",
        },
      }
    end

    function Api:findBooksByIsbns(isbns)
      table.insert(isbn_calls, isbns)
      if isbns[1] == "9788932471631" then
        return {
          {
            book_id = 428232,
            edition_id = 32454164,
            isbn_13 = "9788932471631",
            title = "The Selfish Gene",
            contributions = { author = "Richard Dawkins" },
          },
        }
      end
      return {}
    end

    local hardcover = Hardcover:new {}
    local results, err = hardcover:findBooksByMetadata(
      "이기적 유전자",
      "리처드 도킨스",
      7
    )

    assert.is_nil(err)
    assert.are.same({
      { title = "이기적 유전자", author = "리처드 도킨스" },
      { title = "이기적 유전자", author = nil },
    }, aladin_calls)
    assert.are.same({
      { "9780306406157" },
      { "9788932471631" },
    }, isbn_calls)
    assert.are.equal(1, #results)
    assert.are.equal("이기적 유전자 - 2010년 전면개정판", results[1].title)
    assert.are.equal("The Selfish Gene", results[1].hardcover_title)
  end)
end)
