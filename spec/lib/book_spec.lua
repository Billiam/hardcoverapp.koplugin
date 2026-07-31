local Book = require("hardcover/lib/book")

describe("Book", function()
  describe("parseIdentifiers", function()
    it("parses valid ISBN-10 values", function()
      local identifiers = "isbn:0-306-40615-2"
      local expected = {
        isbn_10 = "0306406152"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("parses valid ISBN-13 values with spaces and hyphens", function()
      local identifiers = "isbn 13: 979-11 6484-326-8"
      local expected = {
        isbn_13 = "9791164843268"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("parses ISBN-10 check digits ending in X", function()
      local identifiers = "isbn: 0-8044-2957-X"
      local expected = {
        isbn_10 = "080442957X"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("ignores identifiers with invalid ISBN checksums", function()
      local identifiers = [[
isbn:0-306-40615-3
isbn13:978-0-306-40615-8
]]
      assert.are.same({}, Book:parseIdentifiers(identifiers))
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

    it("parses hardcover-slug", function()
      local identifiers = "HARDCOVER-SLUG:1984"
      local expected = {
        book_slug = "1984"
      }
      assert.are.same(expected, Book:parseIdentifiers(identifiers))
    end)

    it("does not interpret numeric Hardcover identifiers as ISBNs", function()
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
