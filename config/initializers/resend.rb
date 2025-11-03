require 'resend'

class ResendDeliveryMethod
  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    # Get API key at delivery time, not initialization time
    api_key = @settings[:api_key] || ENV['RESEND_API_KEY']
    
    # Validate API key
    if api_key.blank?
      raise ArgumentError, "Resend API key is missing. Please set RESEND_API_KEY environment variable."
    end
    
    # Set the global API key as per Resend documentation
    Resend.api_key = api_key.to_s.strip
    
    params = {
      from: mail.from.first,
      to: mail.to,
      subject: mail.subject
    }
    
    # Handle text vs HTML content properly
    if mail.text_part&.body
      # Multipart email with text part
      params[:text] = mail.text_part.body.to_s
      if mail.html_part&.body
        params[:html] = mail.html_part.body.to_s
      end
    else
      # Single part email - determine if it's HTML or text
      body_content = mail.body.to_s
      if mail.content_type&.include?('text/html')
        params[:html] = body_content
      else
        # Default to text for plain emails
        params[:text] = body_content
      end
    end
    
    # Use Resend::Emails.send as per documentation
    Resend::Emails.send(params)
  end
end

# Register the custom delivery method
ActionMailer::Base.add_delivery_method :resend, ResendDeliveryMethod