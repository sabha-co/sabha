class Accounts::BotsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action :set_bot, only: %i[ edit update destroy ]

  def index
    @bots = User.active_bots.ordered.includes(:webhook)
    @bot_invite_code = Current.account.active_bot_invite_code
  end

  def new
    @bot = User.active_bots.new
    load_editor
  end

  def edit
    load_editor(selected_room_ids: @bot.room_memberships.map(&:room_id))
  end

  def create
    @bot = User.active_bots.new(name: editor_name)
    return render_editor(:new) unless @bot.valid?(:editor)

    @bot = User.create_bot!(name: editor_name, webhook_url: bot_params[:webhook_url])
    @bot.sync_rooms!(submitted_room_ids, actor: Current.user)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_bots_url, notice: "#{@bot.name} created" }
    end
  rescue ActiveRecord::RecordInvalid => e
    absorb_record_errors(e)
    render_editor(:new)
  end

  def update
    @bot.name = editor_name
    return render_editor(:edit) unless @bot.valid?(:editor)

    @bot.update_bot!(name: editor_name, webhook_url: bot_params[:webhook_url])
    @bot.sync_rooms!(submitted_room_ids, actor: Current.user)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_bots_url, notice: "#{@bot.name} updated" }
    end
  rescue ActiveRecord::RecordInvalid => e
    absorb_record_errors(e)
    render_editor(:edit)
  end

  def destroy
    @bot.deactivate

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to account_bots_url, notice: "#{@bot.name} removed" }
    end
  end

  private
    def set_bot
      @bot = User.active_bots.find(params[:id])
    end

    def bot_params
      params.require(:user).permit(:name, :webhook_url, room_ids: [])
    end

    def editor_name
      bot_params[:name].to_s.strip
    end

    def submitted_room_ids
      Array(bot_params[:room_ids]).reject(&:blank?)
    end

    def absorb_record_errors(error)
      if error.record.is_a?(Webhook)
        # Surface the webhook's own message (bad format, unresolvable host, or a
        # private-network target) under the webhook field rather than a generic line.
        error.record.errors[:url].each { |message| @bot.errors.add(:webhook_url, message) }
      elsif error.record != @bot
        @bot.errors.merge!(error.record.errors)
      end
    end

    def render_editor(template)
      @bot.name = editor_name
      load_editor(selected_room_ids: submitted_room_ids)
      # A failed editor submit replaces the dialog's frame with the re-rendered
      # form, so it must answer as HTML even when the request preferred a stream.
      render template, status: :unprocessable_entity, formats: :html
    end

    def load_editor(selected_room_ids: [])
      @rooms = Room.active.without_directs.without_threads.ordered
      @selected_room_ids = selected_room_ids.map(&:to_i).to_set
      @webhook_url = params[:user].present? ? bot_params[:webhook_url] : @bot.webhook_url
    end
end
