# letter_opener that keeps the browser closed for mail an automated client
# asked for. The mailer marks such mail with ApplicationMailer::AUTOMATED_CLIENT_HEADER;
# everything else previews in a tab exactly as the gem does.
require "letter_opener"

module LetterOpener
  class QuietForAutomatedClients < DeliveryMethod
    def deliver!(mail)
      return super unless mail[ApplicationMailer::AUTOMATED_CLIENT_HEADER]

      validate_mail!(mail)
      location = File.join(settings[:location], "#{Time.now.to_f.to_s.tr(".", "_")}_#{Digest::SHA1.hexdigest(mail.encoded)[0..6]}")
      Message.rendered_messages(mail, location: location, message_template: settings[:message_template])
    end
  end
end
