local BookSearch = require("hardcover/lib/book_search")

describe("BookSearch", function()
  describe("normalizeTitle", function()
    it("removes Korean subtitles after common separators", function()
      assert.are.equal("소년이 온다", BookSearch:normalizeTitle("소년이 온다: 한강 장편소설"))
      assert.are.equal("아몬드", BookSearch:normalizeTitle("아몬드 — 손원평 장편소설"))
      assert.are.equal(
        "아인슈타인의 냉장고",
        BookSearch:normalizeTitle("아인슈타인의 냉장고: 뜨거운 것과 차가운 것의 차이로 우주를 설명하다")
      )
    end)

    it("removes conservative edition and volume qualifiers", function()
      assert.are.equal("불편한 편의점", BookSearch:normalizeTitle("불편한 편의점 (40만 부 기념 리커버 에디션)"))
      assert.are.equal("해리 포터와 마법사의 돌", BookSearch:normalizeTitle("해리 포터와 마법사의 돌 1권"))
      assert.are.equal("토지", BookSearch:normalizeTitle("토지 [제2권]"))
      assert.are.equal("태백산맥", BookSearch:normalizeTitle("태백산맥 (3)"))
      assert.are.equal("작별하지 않는다", BookSearch:normalizeTitle("작별하지 않는다 (장편소설)"))
    end)

    it("keeps meaningful parenthetical text", function()
      assert.are.equal("아몬드 (손원평 장편소설)", BookSearch:normalizeTitle("아몬드 (손원평 장편소설)"))
    end)

    it("does not change non-Korean titles", function()
      local title = "The Hobbit: There and Back Again"
      assert.are.equal(title, BookSearch:normalizeTitle(title))
    end)
  end)

  describe("normalizeAuthor", function()
    it("removes Korean author role suffixes", function()
      assert.are.equal("한강", BookSearch:normalizeAuthor("한강 지음"))
      assert.are.equal("김영하, 정세랑", BookSearch:normalizeAuthor("김영하 저; 정세랑 글"))
    end)

    it("drops translators when a primary author is present", function()
      assert.are.equal("조지 오웰", BookSearch:normalizeAuthor("조지 오웰 지음, 김승욱 옮김"))
      assert.are.equal("폴 센", BookSearch:normalizeAuthor("폴 센 지음; 박병철 옮김"))
    end)

    it("keeps names containing a one-syllable role fragment", function()
      assert.are.equal("저우싱츠", BookSearch:normalizeAuthor("저우싱츠"))
    end)

    it("does not change non-Korean authors", function()
      assert.are.equal("Han Kang", BookSearch:normalizeAuthor("Han Kang"))
    end)
  end)

  describe("metadata", function()
    it("keeps original and normalized Korean metadata separately", function()
      local metadata = BookSearch:metadata(
        "소년이 온다: 한강 장편소설",
        "한강 지음, 데버라 스미스 옮김"
      )

      assert.are.equal("소년이 온다: 한강 장편소설", metadata.original_title)
      assert.are.equal("한강 지음, 데버라 스미스 옮김", metadata.original_author)
      assert.are.equal("소년이 온다", metadata.normalized_title)
      assert.are.equal("한강", metadata.normalized_author)
      assert.is_true(metadata.is_korean)
      assert.is_true(metadata.normalized_changed)
    end)

    it("leaves non-Korean search metadata unchanged", function()
      local metadata = BookSearch:metadata("The Vegetarian", "Han Kang")

      assert.are.equal(metadata.original_title, metadata.normalized_title)
      assert.are.equal(metadata.original_author, metadata.normalized_author)
      assert.is_false(metadata.is_korean)
      assert.is_false(metadata.normalized_changed)
    end)
  end)

  describe("findBestMatch", function()
    it("selects the best title and author match instead of the first result", function()
      local metadata = BookSearch:metadata("작별하지 않는다", "한강 지음")
      local wrong = {
        title = "작별하지 않는다",
        contributions = { author = "다른 작가" },
      }
      local expected = {
        title = "작별하지 않는다",
        contributions = { { author = { name = "한강" } } },
      }

      assert.is_nil(BookSearch:findBestMatch(metadata, { wrong }))
      assert.are.equal(expected, BookSearch:findBestMatch(metadata, { wrong, expected }))
    end)

    it("accepts a result matching a normalized Korean title", function()
      local metadata = BookSearch:metadata("소년이 온다: 한강 장편소설", "한강 지음")
      local expected = {
        title = "소년이 온다",
        contributions = { author = "한강" },
      }

      assert.are.equal(expected, BookSearch:findBestMatch(metadata, { expected }))
    end)

    it("accepts near-exact titles when Hardcover romanizes a Korean author", function()
      local metadata = BookSearch:metadata("소년이 온다: 한강 장편소설", "한강 지음")
      local expected = {
        title = "소년이 온다",
        contributions = {
          author = {
            { name = "Han Kang" },
          },
        },
      }

      assert.are.equal(expected, BookSearch:findBestMatch(metadata, { expected }))
    end)

    it("rejects unrelated search results", function()
      local metadata = BookSearch:metadata("채식주의자", "한강")
      local result = {
        title = "The Vegetarian",
        contributions = { author = "Deborah Smith" },
      }

      assert.is_nil(BookSearch:findBestMatch(metadata, { result }))
    end)

    it("does not link unrelated live results for a missing Korean edition", function()
      local metadata = BookSearch:metadata(
        "아인슈타인의 냉장고: 뜨거운 것과 차가운 것의 차이로 우주를 설명하다",
        "폴 센 지음; 박병철 옮김"
      )
      local results = {
        {
          title = "1985 인구 및 주택 센서스 보고",
          contributions = { author = { { name = "Korea (South)" } } },
        },
        {
          title = "병약한 남주를 꼬셔버렸다 1",
          contributions = { author = { { name = "Senri" }, { name = "센리" } } },
        },
        {
          title = "마음의 장기 심장",
          contributions = { author = { { name = "B-MADE 센터 외 8명" } } },
        },
      }

      assert.is_nil(BookSearch:findBestMatch(metadata, results))
    end)

    it("keeps obvious non-Korean matches working", function()
      local metadata = BookSearch:metadata("The Hobbit", "J. R. R. Tolkien")
      local result = {
        title = "The Hobbit",
        contributions = { author = "J.R.R. Tolkien" },
      }

      assert.are.equal(result, BookSearch:findBestMatch(metadata, { result }))
    end)
  end)
end)
