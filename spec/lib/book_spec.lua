local Book = require("lib/book")

describe("Book", function()
  describe("parseIdentifiers", function()
    it("parses 10 character strings as isbn10", function()
      local identifiers = "asin:1234567890"
      local expected = {
        isbn_10 = "1234567890"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("parses 13 character strings as isbn13", function()
      local identifiers = "asin 13:1234567890123"
      local expected = {
        isbn_13 = "1234567890123"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("parses hardcover book and editions", function()
      local identifiers = [[
HARDCOVER:the-hobbit
HARDCOVER-EDITION:16193290
]]

      local expected = {
        book_slug = "the-hobbit",
        edition_id = "16193290"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("prioritizes hardcover editions over isbn", function()
      local identifiers = [[
HARDCOVER:1234567890
HARDCOVER-EDITION:1234567890123
]]

      local expected = {
        book_slug = "1234567890",
        edition_id = "1234567890123"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)
  end)
end)
