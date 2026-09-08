module NotifyBots
  extend ActiveSupport::Concern

  private
    def notify_bots(item, event)
      Bot::Event.new(item, event, base_url: request.base_url + request.script_name).dispatch
    end
end
