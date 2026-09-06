require "application_system_test_case"

class JumpToNewestTest < ApplicationSystemTestCase
  setup do
    sign_in "kevin@37signals.com"
    room = rooms(:designers)
    messages = 40.times.map do |i|
      room.messages.create!(creator: [ users(:jason), users(:david) ][i % 2], body: "Jump history #{i}",
        client_message_id: "jump_history_#{i}", created_at: (50 - i).minutes.ago)
    end
    visit room_at_message_path(room, messages[15])
    dismiss_pwa_install_prompt
    assert_selector ".search-highlight"

    # Hold only pagination requests. The real controller, paginator, observers,
    # fetch response parsing and Turbo stream rendering all remain in use.
    execute_script <<~JS
      window.jumpRequests = []
      const originalFetch = window.fetch
      const messagesURL = new URL(document.querySelector('#message-area').dataset.messagesPageUrlValue)
      window.fetch = (url, options) => {
        if (new URL(url, location.href).pathname !== messagesURL.pathname) return originalFetch(url, options)
        return new Promise((resolve, reject) => {
          jumpRequests.push({ url: new URL(url, location.href), resolve, reject })
          document.body.dataset.jumpRequestCount = jumpRequests.length
        })
      }
      window.jumpHTML = (id, text) => `<div id="message_jump_${id}" class="message" data-message-id="${id}"
        data-messages-target="message" data-sort-value="${id}" style="min-height: 100px">${text}</div>`
    JS
  end

  test "HTTP failure keeps history and allows another jump" do
    assert_failed_jump_can_retry "jumpRequests[0].resolve(new Response('Unavailable', { status: 500 }))"
  end

  test "network failure clears busy state and allows another jump" do
    assert_failed_jump_can_retry "jumpRequests[0].reject(new TypeError('Offline'))"
  end

  test "repeated jumps share a request and preserve live arrivals" do
    start_jump
    # Exercise another caller while the first jump is pending (also used by the
    # composer), regardless of whether the button itself is disabled.
    execute_script <<~JS
      const controller = Stimulus.getControllerForElementAndIdentifier(document.querySelector('#message-area'), 'messages')
      window.secondJump = controller.returnToLatest()
      Turbo.renderStreamMessage(`<turbo-stream action="append" target="${controller.messagesTarget.id}">
        <template>${jumpHTML(901, 'Also in snapshot')}</template></turbo-stream>`)
      Turbo.renderStreamMessage(`<turbo-stream action="append" target="${controller.messagesTarget.id}">
        <template>${jumpHTML(902, 'Arrived during jump')}</template></turbo-stream>`)
    JS
    # Let Turbo enter its asynchronous render before completing the snapshot.
    page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
    assert_equal 1, page.evaluate_script("jumpRequests.length")
    release_page 0, "jumpHTML(900, 'Latest snapshot') + jumpHTML(901, 'Snapshot end')"

    assert_selector "#message_jump_902", text: "Arrived during jump", count: 1
    assert_selector "#message_jump_901", count: 1
    assert_no_selector ".message-area__return-to-latest.busy"
    assert_equal %w[900 901 902], displayed_ids
    assert_at_bottom
  end

  test "a pending forward page cannot append old messages after a jump" do
    assert_stale_page_ignored "messages.scrollHeight", "after"
  end

  test "a deletion received during a jump stays after its queued append" do
    start_jump
    stream_message_during_jump
    execute_script 'Turbo.renderStreamMessage(`<turbo-stream action="remove" target="message_jump_902"></turbo-stream>`)'
    settle_streams
    release_page 0, "jumpHTML(900, 'Snapshot before creation')"
    settle_requests

    assert_no_selector "#message_jump_902", visible: :all
  end

  test "an edit received during a jump stays after its queued append" do
    start_jump
    stream_message_during_jump
    execute_script <<~JS
      Turbo.renderStreamMessage(`<turbo-stream action="replace" target="presentation_jump_902" maintain_scroll>
        <template><div id="presentation_jump_902">Edited during jump</div></template></turbo-stream>`)
    JS
    settle_streams
    release_page 0, "jumpHTML(900, 'Snapshot before creation')"

    assert_selector "#presentation_jump_902", text: "Edited during jump"
    assert_equal %w[900 902], displayed_ids
  end

  test "a failed history fetch restores unsent files alongside newly selected files" do
    page.evaluate_async_script <<~JS
      const done = arguments[0]
      import('models/file_uploader').then(({ default: FileUploader }) => {
        window.uploadedFiles = []
        FileUploader.prototype.upload = async function() { uploadedFiles.push(this.file.name); return '' }
        window.sendErrors = []
        window.addEventListener('unhandledrejection', event => { sendErrors.push(event.reason.message); event.preventDefault() })
        done()
      })
    JS
    pick_files "first.txt", "second.txt"
    submit_composer
    wait_for_requests 1
    pick_files "new.txt"
    execute_script "jumpRequests[0].resolve(new Response('Unavailable', { status: 500 }))"

    assert_selector ".composer__file", count: 3
    assert_equal [], page.evaluate_script("uploadedFiles")
    assert_equal [], page.evaluate_script("sendErrors")

    submit_composer
    wait_for_requests 2
    release_page 1, "jumpHTML(900, 'Recovered latest page')"
    assert_selector ".message__pending-upload", count: 3
    assert_equal %w[first.txt new.txt second.txt], page.evaluate_script("uploadedFiles.slice().sort()")
    assert_no_selector ".composer__file"
  end

  test "an edit to an existing target waits without blocking the scroll queue" do
    start_jump
    execute_script <<~JS
      const message = document.querySelector('#message-area .messages [data-message-id]')
      window.existingMessageHTML = message.outerHTML
      const edited = message.cloneNode(true)
      edited.innerHTML = 'Edited existing target'
      const target = document.querySelector('#message-area .messages').id
      Turbo.renderStreamMessage(`<turbo-stream action="append" target="${target}"><template>${message.outerHTML}</template></turbo-stream>`)
      Turbo.renderStreamMessage(`<turbo-stream action="replace" target="${message.id}" maintain_scroll><template>${edited.outerHTML}</template></turbo-stream>`)
    JS
    settle_streams
    release_page 0, "existingMessageHTML"

    assert_text "Edited existing target"
    assert_no_selector ".message-area__return-to-latest.busy"
  end

  test "a failed jump releases queued edits so the next jump can render" do
    start_jump
    execute_script <<~JS
      const message = document.querySelector('#message-area .messages [data-message-id]')
      const edited = message.cloneNode(true)
      edited.innerHTML = 'History edit during failed jump'
      Turbo.renderStreamMessage(`<turbo-stream action="replace" target="${message.id}" maintain_scroll><template>${edited.outerHTML}</template></turbo-stream>`)
    JS
    stream_message_during_jump
    execute_script "jumpRequests[0].resolve(new Response('Unavailable', { status: 500 }))"
    settle_requests
    assert_selector ".message-area__return-to-latest:not(.busy)", visible: true
    assert_text "History edit during failed jump"
    assert_no_selector "#message_jump_902"

    start_jump 2
    stream_message_during_jump
    release_page 1, "jumpHTML(900, 'Recovered snapshot')"
    assert_selector "#message_jump_902"
    assert_equal %w[900 902], displayed_ids
  end

  test "a failed history fetch preserves the text draft without an unhandled rejection" do
    execute_script <<~JS
      window.sendErrors = []
      window.addEventListener('unhandledrejection', event => { sendErrors.push(event.reason.message); event.preventDefault() })
    JS
    fill_in_rich_text_area "message_body", with: "Keep this draft"
    submit_composer
    wait_for_requests 1
    execute_script "jumpRequests[0].resolve(new Response('Unavailable', { status: 500 }))"
    settle_streams

    assert_equal [], page.evaluate_script("sendErrors")
    assert_selector "#composer lexxy-editor", text: "Keep this draft"
    submit_composer
    wait_for_requests 2
    release_page 1, "jumpHTML(900, 'Recovered snapshot')"
    assert_selector "#message-area .message:not([data-message-id])", text: "Keep this draft"
  end

  test "a pending backward page cannot prepend old messages after a jump" do
    assert_stale_page_ignored "0", "before"
  end

  test "scrolling during a jump does not start another page fetch" do
    start_jump
    execute_script <<~JS
      const messages = document.querySelector('#message-area .messages')
      messages.scrollTop = 0
      messages.scrollTop = messages.scrollHeight
    JS
    settle_streams
    assert_equal 1, page.evaluate_script("jumpRequests.length")
    release_page 0, "jumpHTML(900, 'Latest snapshot')"
    assert_selector "#message_jump_900"
  end

  test "live appends during a retry are not dropped by a failed jump's queue" do
    start_jump
    stream_message_during_jump
    execute_script "jumpRequests[0].resolve(new Response('Unavailable', { status: 500 }))"
    start_jump 2
    execute_script <<~JS
      const target = document.querySelector('#message-area .messages').id
      Turbo.renderStreamMessage(`<turbo-stream action="append" target="${target}">
        <template>${jumpHTML(903, 'Arrived during retry')}</template></turbo-stream>`)
    JS
    settle_streams
    release_page 1, "jumpHTML(900, 'Recovered snapshot')"
    settle_requests
    assert_selector "#message_jump_903", text: "Arrived during retry"
    assert_equal %w[900 903], displayed_ids
  end

  test "disconnecting during a jump prevents the response from replacing history" do
    original_ids = displayed_ids
    start_jump
    execute_script <<~JS
      window.detachedMessageArea = document.querySelector('#message-area')
      detachedMessageArea.remove()
    JS
    page.evaluate_async_script("requestAnimationFrame(arguments[0])")
    release_page 0, "jumpHTML(900, 'Detached response')"
    settle_requests

    assert_equal original_ids, page.evaluate_script("Array.from(detachedMessageArea.querySelectorAll('.messages [data-message-id]'), el => el.dataset.messageId)")
  end

  test "an empty latest page clears obsolete history" do
    start_jump
    execute_script "jumpRequests[0].resolve(new Response(null, { status: 204 }))"
    assert_no_selector ".message-area__return-to-latest", visible: true
    assert_equal [], displayed_ids
  end

  private
    def stream_message_during_jump
      execute_script <<~JS
        const target = document.querySelector('#message-area .messages').id
        Turbo.renderStreamMessage(`<turbo-stream action="append" target="${target}">
          <template>${jumpHTML(902, '<div id="presentation_jump_902">Original message</div>')}</template></turbo-stream>`)
      JS
      settle_streams
    end

    def settle_streams
      page.evaluate_async_script("requestAnimationFrame(() => requestAnimationFrame(arguments[0]))")
    end

    def pick_files(*names)
      execute_script <<~JS
        const composer = Stimulus.getControllerForElementAndIdentifier(document.querySelector('#composer'), 'composer')
        composer.filePicked({ target: { files: #{names.to_json}.map(name => new File(['hello'], name, { type: 'text/plain' })), value: '' } })
      JS
    end

    def submit_composer
      execute_script <<~JS
        const composer = Stimulus.getControllerForElementAndIdentifier(document.querySelector('#composer'), 'composer')
        composer.fieldsTarget.disabled = false
        composer.submit({ preventDefault() {} })
      JS
    end

    def assert_stale_page_ignored(scroll_top, direction)
      execute_script <<~JS
        const messages = document.querySelector('#message-area .messages')
        messages.scrollTop = #{scroll_top}
      JS
      wait_for_requests 1
      assert page.evaluate_script("jumpRequests[0].url.searchParams.has('#{direction}')")

      start_jump 2
      release_page 1, "jumpHTML(900, 'Latest snapshot') + jumpHTML(901, 'Snapshot end')"
      assert_selector "#message_jump_901"
      release_page 0, "jumpHTML(102, 'Stale history page')"
      settle_requests

      assert_equal %w[900 901], displayed_ids
      assert_no_text "Stale history page"
    end

    def start_jump(request_count = 1)
      execute_script <<~JS
        const controller = Stimulus.getControllerForElementAndIdentifier(document.querySelector('#message-area'), 'messages')
        window.jumpFinished = controller.returnToLatest().catch(error => { window.jumpError = error.message })
      JS
      wait_for_requests request_count
    end

    def wait_for_requests(count)
      assert_selector "body[data-jump-request-count='#{count}']"
    end

    def release_page(index, html)
      execute_script "jumpRequests[#{index}].resolve(new Response(#{html}, { status: 200, headers: { 'Content-Type': 'text/html' } }))"
    end

    def settle_requests
      page.evaluate_async_script <<~JS
        const done = arguments[0]
        Promise.resolve(window.jumpFinished).then(() => requestAnimationFrame(() => requestAnimationFrame(done)))
      JS
    end

    def assert_failed_jump_can_retry(failure)
      original_ids = displayed_ids
      start_jump
      execute_script failure
      settle_requests

      assert_selector ".message-area__return-to-latest:not(.busy)", visible: true
      assert_equal original_ids, displayed_ids
      start_jump 2
      release_page 1, "jumpHTML(900, 'Recovered latest page')"
      assert_selector "#message_jump_900"
      assert_no_selector ".message-area__return-to-latest", visible: true
      assert_at_bottom
    end

    def displayed_ids
      page.evaluate_script("Array.from(document.querySelectorAll('#message-area .messages [data-message-id]'), el => el.dataset.messageId)")
    end

    def assert_at_bottom
      distance = page.evaluate_script <<~JS
        (() => { const el = document.querySelector('#message-area .messages'); return el.scrollHeight - el.scrollTop - el.clientHeight })()
      JS
      assert_operator distance, :<=, 4
    end
end
