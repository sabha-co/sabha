module UsersHelper
  def button_to_direct_room_with(user)
    button_to rooms_directs_path(user_ids: [ user.id ]), class: "btn btn--primary full-width txt--large" do
      image_tag("messages.svg")
    end
  end
end
