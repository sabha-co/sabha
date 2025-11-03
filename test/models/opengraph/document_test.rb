require "test_helper"

class Opengraph::DocumentTest < ActiveSupport::TestCase
  test "extract opengraph tags using property attribute" do
    document = Opengraph::Document.new("<html><head><meta property=\"og:url\" content=\"https://example.com\"><meta property=\"og:title\" content=\"Hey!\"><meta property=\"og:description\" content=\"desc..\"><meta property=\"og:image\" content=\"https://example.com/image.png\"></head></html>")
    attributes = document.opengraph_attributes

    assert_equal "https://example.com", attributes[:url]
    assert_equal "Hey!", attributes[:title]
    assert_equal "desc..", attributes[:description]
    assert_equal "https://example.com/image.png", attributes[:image]
  end

  test "extract opengraph tags using name attribute" do
    document = Opengraph::Document.new("<html><head><meta name=\"og:url\" content=\"https://example.com\"><meta name=\"og:title\" content=\"Hey!\"><meta name=\"og:description\" content=\"desc..\"><meta name=\"og:image\" content=\"https://example.com/image.png\"></head></html>")
    attributes = document.opengraph_attributes

    assert_equal "https://example.com", attributes[:url]
    assert_equal "Hey!", attributes[:title]
    assert_equal "desc..", attributes[:description]
    assert_equal "https://example.com/image.png", attributes[:image]
  end

  test "document containing missing meta encoding tag and non-UTF8 characters" do
    document = Opengraph::Document.new("<html><head><meta name=\"og:url\" content=\"https://example.com\"><meta name=\"og:title\" content=\"Hey!\"><meta name=\"og:description\" content=\"Hello â\u0080\u0099World\"><meta name=\"og:image\" content=\"https://example.com/image.png\"></head></html>")
    attributes = document.opengraph_attributes

    assert_equal "https://example.com", attributes[:url]
    assert_equal "Hey!", attributes[:title]
    assert_equal "Hello World", attributes[:description]
    assert_equal "https://example.com/image.png", attributes[:image]
  end
end
