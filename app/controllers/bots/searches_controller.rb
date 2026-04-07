class Bots::SearchesController < Bots::BaseController
  include ActiveStorage::SetCurrent

  def index
    query = params[:q].to_s.gsub(/[^[:word:]]/, " ").strip
    return render(json: { error: "Query parameter 'q' is required", code: "validation_failed" }, status: :unprocessable_entity) if query.blank?

    messages = Current.user.reachable_messages
                           .active
                           .search(query)
                           .with_creator
                           .includes(:room)
                           .limit(50)

    render json: messages.map { |msg|
      {
        id: msg.id,
        creator: { id: msg.creator.id, name: msg.creator.name },
        body: { html: msg.body.body.to_s, plain: msg.plain_text_body },
        room: { id: msg.room.id, name: msg.room.name },
        created_at: msg.created_at.iso8601
      }
    }
  end
end
