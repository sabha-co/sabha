class ApplicationPlatform < PlatformAgent
  attr_reader :client

  def initialize(user_agent_string, client: nil)
    super(user_agent_string)
    @client = client
  end

  def ios?
    match? /iPhone|iPad/
  end

  def android?
    match? /Android/
  end

  def mac?
    match? /Macintosh/
  end

  def chrome?
    user_agent.browser.match? /Chrome/
  end

  def firefox?
    user_agent.browser.match? /Firefox|FxiOS/
  end

  def safari?
    user_agent.browser.match? /Safari/
  end

  def edge?
    user_agent.browser.match? /Edg/
  end

  def apple_messages?
    # Apple Messages pretends to be Facebook and Twitter bots via spoofed user agent.
    # We want to avoid showing "Unsupported browser" message when a Sabha link
    # is shared via Messages.
    match?(/facebookexternalhit/i) && match?(/Twitterbot/i)
  end

  def mobile?
    ios? || android?
  end

  # Sabha's own apps name themselves in the Sabha-Client header ("desktop",
  # later "mobile"). Not to be confused with `desktop?`, which only means
  # "not a phone".
  def desktop_app?
    client == "desktop"
  end

  def desktop?
    !mobile?
  end

  def windows?
    operating_system == "Windows"
  end

  def operating_system
    case user_agent.platform
    when /Android/   then "Android"
    when /iPad/      then "iPad"
    when /iPhone/    then "iPhone"
    when /Macintosh/ then "macOS"
    when /Windows/   then "Windows"
    when /CrOS/      then "ChromeOS"
    else
      os =~ /Linux/ ? "Linux" : os
    end
  end
end
