local ReviewFormat = require("hardcover/lib/review_format")

describe("ReviewFormat", function()
  describe("buildSlateDocument", function()
    it("wraps a single paragraph in the legacy Slate document shape", function()
      local result = ReviewFormat.buildSlateDocument("Hello world.")

      assert.are.same({
        document = {
          object = "document",
          children = {
            {
              data = {},
              type = "paragraph",
              object = "block",
              children = {
                { text = "Hello world.", object = "text" }
              }
            }
          }
        }
      }, result)
    end)

    it("splits paragraphs on double newlines", function()
      local result = ReviewFormat.buildSlateDocument("First paragraph.\n\nSecond paragraph.")

      assert.are.equal(2, #result.document.children)
      assert.are.equal("First paragraph.", result.document.children[1].children[1].text)
      assert.are.equal("Second paragraph.", result.document.children[2].children[1].text)
    end)

    it("returns nil for empty input", function()
      assert.is_nil(ReviewFormat.buildSlateDocument(""))
    end)

    it("returns nil for whitespace-only input", function()
      assert.is_nil(ReviewFormat.buildSlateDocument("   \n\n  \t  "))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(ReviewFormat.buildSlateDocument(nil))
    end)
  end)
end)
