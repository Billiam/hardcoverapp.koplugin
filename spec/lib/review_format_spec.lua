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

    it("ignores leading double newlines", function()
      local result = ReviewFormat.buildSlateDocument("\n\nActual text.")

      assert.are.equal(1, #result.document.children)
      assert.are.equal("Actual text.", result.document.children[1].children[1].text)
    end)

    it("ignores trailing double newlines", function()
      local result = ReviewFormat.buildSlateDocument("Actual text.\n\n")

      assert.are.equal(1, #result.document.children)
      assert.are.equal("Actual text.", result.document.children[1].children[1].text)
    end)

    it("collapses multiple consecutive blank lines", function()
      local result = ReviewFormat.buildSlateDocument("First.\n\n\n\nSecond.")

      assert.are.equal(2, #result.document.children)
      assert.are.equal("First.", result.document.children[1].children[1].text)
      assert.are.equal("Second.", result.document.children[2].children[1].text)
    end)

    it("treats a single newline as part of the paragraph, not a separator", function()
      local result = ReviewFormat.buildSlateDocument("Line one.\nLine two.")

      assert.are.equal(1, #result.document.children)
      assert.are.equal("Line one.\nLine two.", result.document.children[1].children[1].text)
    end)
  end)

  describe("hasRichFormatting", function()
    it("returns false for a single plain paragraph", function()
      assert.is_false(ReviewFormat.hasRichFormatting("<p>Just plain text.</p>"))
    end)

    it("returns false for multiple plain paragraphs with line breaks", function()
      assert.is_false(ReviewFormat.hasRichFormatting("<p>One.</p><p>Two.<br>still two.</p>"))
    end)

    it("returns false for nil or empty input", function()
      assert.is_false(ReviewFormat.hasRichFormatting(nil))
      assert.is_false(ReviewFormat.hasRichFormatting(""))
    end)

    it("returns false for the empty-paragraph artifact <p><br></p>", function()
      assert.is_false(ReviewFormat.hasRichFormatting("<p><br></p>"))
    end)

    it("returns true when there is bold markup", function()
      assert.is_true(ReviewFormat.hasRichFormatting("<p>Some <strong>bold</strong> text.</p>"))
    end)

    it("returns true when there is a link", function()
      assert.is_true(ReviewFormat.hasRichFormatting('<p>See <a href="x">this</a>.</p>'))
    end)

    it("returns true when there is italic markup", function()
      assert.is_true(ReviewFormat.hasRichFormatting("<p>Some <em>italic</em> text.</p>"))
    end)
  end)
end)
