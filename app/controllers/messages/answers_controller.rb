class Messages::AnswersController < ApplicationController
  before_action :set_message
  before_action :ensure_can_answer

  def create
    @message.answer_by(Current.user)
    broadcast_message_update
  end

  def destroy
    @message.undo_answer_by(Current.user)
    broadcast_message_update
  end

  private

  def set_message
    @message = Message.active.find(params[:message_id])
  end

  def broadcast_message_update
    action_html = render_to_string(partial: "messages/actions/answer", locals: { message: @message })
    @message.broadcast_replace_to @message.room, :messages, target: [ @message, :answering ], html: action_html
    @message.broadcast_replace_to :inbox, target: [ @message, :answering ], html: action_html

    meta_html = render_to_string(partial: "messages/answered_by", locals: { message: @message })
    @message.broadcast_replace_to @message.room, :messages, target: [ @message, :answered_by ], html: meta_html
    @message.broadcast_replace_to :inbox, target: [ @message, :answered_by ], html: meta_html
  end

  def ensure_can_answer
    head :forbidden unless Current.user.expert? || Current.user.administrator?
  end
end
