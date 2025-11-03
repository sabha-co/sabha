class GumroadAPI
  BASE_URL = "https://api.gumroad.com/v2"

  class << self
    attr_accessor :access_token

    def successful_membership_sale(email:)
      product_ids.lazy.map { |product_id| successful_sales(email:, product_id:).first }.find(&:itself)
    end

    def successful_sales(params = {})
      all_sales = get("/sales", params)["sales"] || []

      # Ignore gift purchases as these are returned via match on buyer's email and not the giftee email
      all_sales.reject { |sale| sale["refunded"] || sale["chargedback"] || sale["is_gift_sender_purchase"] }
    end

    def resource_subscriptions(resource_name)
      get("/resource_subscriptions", { resource_name: })
    end

    def subscribe(resource_name, post_url)
      put("/resource_subscriptions", {
        resource_name:,
        post_url:
      })
    end

    def unsubscribe(subscription_id)
      delete("/resource_subscriptions/#{subscription_id}")
    end

    def product_ids
      ENV.fetch("GUMROAD_PRODUCT_IDS", "").split(",").map(&:strip).compact_blank
    end

    private

    def get(endpoint, params = {})
      raise "Access token is not set" unless @access_token

      uri = URI("#{BASE_URL}#{endpoint}")
      params[:access_token] = @access_token
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri)
      handle_response(response)
    end

    def post(endpoint, payload)
      raise "Access token is not set" unless @access_token

      uri = URI("#{BASE_URL}#{endpoint}")
      payload[:access_token] = @access_token

      response = Net::HTTP.post_form(uri, payload)
      handle_response(response)
    end

    def put(endpoint, payload)
      raise "Access token is not set" unless @access_token

      uri = URI("#{BASE_URL}#{endpoint}")
      request = Net::HTTP::Put.new(uri)
      request.set_form_data(payload.merge(access_token: @access_token))

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }

      handle_response(response)
    end

    def delete(endpoint)
      raise "Access token is not set" unless @access_token

      uri = URI("#{BASE_URL}#{endpoint}")
      uri.query = URI.encode_www_form(access_token: @access_token)

      request = Net::HTTP::Delete.new(uri)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }

      handle_response(response)
    end

    def handle_response(response)
      case response
      when Net::HTTPSuccess
        JSON.parse(response.body)
      else
        { "success" => false, "error" => response.message, "code" => response.code }
      end
    end
  end
end
