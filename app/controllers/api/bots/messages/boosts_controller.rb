class API::Bots::Messages::BoostsController < API::Bots::BaseController
  include NotifyBots

  REACTIONS_CAP = 50
  BOOSTERS_CAP = 100

  before_action :set_room_and_message

  def index
    @groups, @total, @truncated = @message.boost_summary(limit: REACTIONS_CAP, boosters_limit: BOOSTERS_CAP)
  end

  def create
    content = request.body.tap(&:rewind).read.force_encoding("UTF-8").strip
    @boost = @message.boosts.create!(content: content, booster: Current.user)

    notify_bots(@boost, :created)

    render json: { id: @boost.id, content: @boost.content }, status: :created
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render json: { error: "Boost already exists or is invalid", code: "validation_failed" }, status: :unprocessable_entity
  end

  def destroy
    @boost = @message.boosts.where(booster: Current.user).find(params[:id])

    @boost.destroy!
    notify_bots(@boost, :deleted)

    head :no_content
  end

  private
    def set_room_and_message
      if params[:room_id]
        @room = Current.user.rooms.find(params[:room_id])
        @message = @room.messages.active.find(params[:message_id])
      else
        @message = Message.active.where(room_id: Current.user.rooms.select(:id)).find(params[:message_id])
        @room = @message.room
      end
    end
end
