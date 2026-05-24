require "test_helper"

class ActionTextSanitizerTest < ActiveSupport::TestCase
  test "ActionText preserves turbo-frame, details, summary, section, and popup data attributes" do
    html = %(<turbo-frame id="popup-1"><details><summary>S</summary><section data-controller="popup" data-action="click->popup#toggle" data-popup-target="content">x</section></details></turbo-frame>)

    rendered = ActionText::Content.new(html).to_rendered_html_with_layout

    assert_includes rendered, "<turbo-frame"
    assert_includes rendered, "<details>"
    assert_includes rendered, "<summary>"
    assert_includes rendered, "<section"
    assert_includes rendered, %(data-controller="popup")
    assert_includes rendered, %(data-action="click->popup#toggle")
    assert_includes rendered, %(data-popup-target="content")
  end

  test "ActionText preserves figure, figcaption, and action-text-attachment with its attributes" do
    sgid = users(:david).attachable_sgid
    html = %(<figure class="attachment"><figcaption>cap</figcaption><action-text-attachment sgid="#{sgid}" caption="hi" content-type="application/vnd.sabha.mention"></action-text-attachment></figure>)

    rendered = ActionText::Content.new(html).to_rendered_html_with_layout

    assert_includes rendered, "<action-text-attachment"
    assert_includes rendered, %(sgid="#{sgid}")
    assert_includes rendered, %(caption="hi")
    assert_includes rendered, %(content-type=)
  end
end
