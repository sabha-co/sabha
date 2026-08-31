require "application_system_test_case"

class BoostingMessagesTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    join_room rooms(:designers)
  end

  test "boosting a message with custom text" do
    open_reaction_picker messages(:third)

    within_reaction_picker do
      fill_in "boost[content]", with: "Good morning"
      click_on "Submit"
    end

    assert_reaction_picker_closed
    within_message messages(:third) do
      assert_boost_text "Good morning"
    end
  end

  test "picking a reaction from the grid" do
    open_reaction_picker messages(:third)

    within_reaction_picker do
      click_on "Party popper"
    end

    assert_reaction_picker_closed
    within_message messages(:third) do
      assert_boost_text "🎉"
    end
  end

  test "the action bar opens an anchored quick-reaction picker" do
    open_action_bar_picker messages(:third)
    assert_no_selector "#reaction_picker_dialog[open]"
    assert_selector ".message-reaction-menu__emoji", count: 15
    assert_no_selector ".message-reaction-menu__emoji[title='Thumbs up']"
    assert_selector ".message-reaction-menu__more"
    assert_selector ".message-reaction-menu__grid > *", count: 16

    within ".message-reaction-menu" do
      click_on "Party popper"
    end

    within_message messages(:third) do
      assert_boost_text "🎉"
    end
    assert_no_selector ".message-reaction-menu", visible: :visible
  end

  test "the action bar picker links to the full reaction picker" do
    open_action_bar_picker messages(:third)

    within ".message-reaction-menu" do
      click_on "More reactions"
    end

    assert_selector "#reaction_picker_dialog[open]"
  end

  test "the action bar picker light dismisses" do
    open_action_bar_picker messages(:third)
    find("#nav").click

    assert_no_selector ".message-reaction-menu", visible: :visible
    within_message messages(:third) do
      assert_equal "false", find(".message__reaction-picker .message__boost-btn", visible: :all)["aria-expanded"]
    end

    open_action_bar_picker messages(:third)
    find("body").send_keys :escape

    assert_no_selector ".message-reaction-menu", visible: :visible
    within_message messages(:third) do
      assert_equal "false", find(".message__reaction-picker .message__boost-btn", visible: :all)["aria-expanded"]
    end
  end

  test "the trailing reaction picker aligns with the reaction chips" do
    messages(:third).boosts.create!(content: "🎉", booster: users(:david))
    visit room_path(rooms(:designers))

    within_message messages(:third) do
      add = find(".boost__add")
      chip = find(".boost__toggle")

      assert_equal "1px", add.evaluate_script("getComputedStyle(this).borderTopWidth")
      assert_in_delta chip.evaluate_script("this.getBoundingClientRect().top + this.getBoundingClientRect().height / 2"),
                      add.evaluate_script("this.getBoundingClientRect().top + this.getBoundingClientRect().height / 2"),
                      1
    end
  end

  test "the picker closes on escape without boosting" do
    open_reaction_picker messages(:third)

    # A bare keyboard escape — element-targeted send_keys clicks the card to
    # focus it, which could land on an emoji cell.
    page.driver.browser.keyboard.type(:Escape)

    assert_reaction_picker_closed
    within_message messages(:third) do
      assert_no_selector ".boost"
    end
  end

  test "clicking the scrim closes the picker" do
    open_reaction_picker messages(:third)

    click_reaction_picker_scrim

    assert_reaction_picker_closed
  end

  test "removing your reaction by clicking your own chip" do
    using_session("David") do
      sign_in "david@37signals.com"
      join_room rooms(:designers)

      # boosts(:first) is David's "Hello" on messages(:first); clicking the chip
      # he's in toggles it back off.
      find(".boost--mine .boost__toggle", text: "Hello").click

      assert_no_text "Hello"
    end
  end

  test "message update preserves the picker input state" do
    within_message messages(:third) do
      assert_message_text "Third time's a charm."
    end

    open_reaction_picker messages(:third)
    within_reaction_picker do
      fill_in "boost[content]", with: "Hey!"
    end

    using_session("JZ") do
      sign_in "jz@37signals.com"
      join_room rooms(:designers)

      within_message messages(:third) do
        reveal_message_actions
        click_on "Edit"

        fill_in_rich_text_area "message_body", with: "Redacted!"
        click_on "Save changes"
      end
    end

    within_message messages(:third) do
      assert_message_text "Redacted!"
    end
    within_reaction_picker do
      assert_boost_input_value "Hey!"
    end
  end

  test "boost by another user preserves the picker input state" do
    open_reaction_picker messages(:third)
    within_reaction_picker do
      fill_in "boost[content]", with: "Hey!"
    end

    using_session("David") do
      sign_in "david@37signals.com"
      join_room rooms(:designers)

      open_reaction_picker messages(:third)
      within_reaction_picker do
        fill_in "boost[content]", with: "Morning"
        click_on "Submit"
      end

      within_message messages(:third) do
        assert_boost_text "Morning"
      end
    end

    perform_enqueued_jobs

    within_message messages(:third) do
      assert_boost_text "Morning"
    end
    within_reaction_picker do
      assert_boost_input_value "Hey!"
    end
  end

  private
    def open_action_bar_picker(message)
      within_message message do
        find(".message__body-content").hover
        find(".message__boost-btn").click
      end

      assert_selector ".message-reaction-menu", visible: :visible
    end

    def open_reaction_picker(message)
      within_message message do
        reveal_message_actions
        click_on "Add reaction"
      end

      assert_selector "#reaction_picker_dialog[open]"
    end

    def within_reaction_picker(&block)
      within "#reaction_picker_dialog", &block
    end

    def assert_reaction_picker_closed
      assert_no_selector "#reaction_picker_dialog[open]"
    end

    def click_reaction_picker_scrim
      # The backdrop isn't a DOM element — a click on it dispatches with the
      # <dialog> itself as the target, which is what this simulates.
      execute_script "document.getElementById('reaction_picker_dialog').click()"
    end

    def assert_boost_input_value(text)
      assert page.has_field?("boost[content]", with: text)
    end

    def assert_boost_text(text, **options)
      assert_selector ".boost", text: text, **options
    end
end
