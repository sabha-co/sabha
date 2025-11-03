module Users::ProfilesHelper
  def profile_form_with(model, **params, &)
    form_with \
      model: @user, url: user_profile_path, method: :patch,
      data: { controller: "form" },
      **params,
      &
  end

  def profile_form_submit_button
    tag.button class: "btn btn--reversed center txt-large", type: "submit" do
      image_tag("check.svg", aria: { hidden: "true" }, size: 20) +
      tag.span("Save changes", class: "for-screen-reader")
    end
  end

  def web_share_session_button(url, title, text, &)
    tag.button class: "btn", hidden: true, data: {
      controller: "web-share", action: "web-share#share",
      web_share_url_value: url,
      web_share_text_value: text,
      web_share_title_value: title
    }, &
  end
end
