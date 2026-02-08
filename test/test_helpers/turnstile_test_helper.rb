module TurnstileTestHelper
  def with_turnstile_response(params)
    params.merge("cf-turnstile-response" => "mocked")
  end
end
