# Renders the social-share (OpenGraph) card for an account as a 1200x630 PNG.
#
# Rather than advertising Sabha on every shared link, the card shows the
# operator's own community: their uploaded logo (or the Sabha mark when none is
# set) above the account name, on a clean brand background with a small "powered
# by sabha" footer.
class Account::OgImage
  WIDTH = 1200
  HEIGHT = 630

  BACKGROUND = [ 255, 255, 255 ]  # white
  INK = [ 32, 33, 36 ]            # #202124
  MUTED = [ 142, 142, 147 ]       # #8e8e93

  MARK_SIZE = 112
  MARK = Rails.root.join("app/assets/images/logos/app-icon.png")

  def initialize(account)
    @account = account
  end

  def png
    compose.write_to_buffer(".png")
  end

  private
    def compose
      title = text(display_name, "sans bold 72", INK)
      footer = text("powered by sabha", "sans 28", MUTED)

      stack = [
        [ mark, 48 ],
        [ title, 20 ],
        [ footer, 0 ]
      ]

      total = stack.sum { |image, gap| image.height + gap }
      top = (HEIGHT - total) / 2

      canvas = background
      stack.each do |image, gap|
        canvas = canvas.composite2(image, :over, x: (WIDTH - image.width) / 2, y: top)
        top += image.height + gap
      end

      canvas.flatten(background: BACKGROUND)
    end

    # The operator's uploaded logo when present (fitted into the mark box,
    # aspect preserved), otherwise the stock Sabha mark.
    def mark
      if @account&.logo&.attached?
        Vips::Image.thumbnail_buffer(@account.logo.download, MARK_SIZE, height: MARK_SIZE, size: :down)
                   .copy(interpretation: "srgb")
      else
        Vips::Image.thumbnail(MARK.to_s, MARK_SIZE)
      end
    end

    def background
      white = (Vips::Image.black(WIDTH, HEIGHT) + BACKGROUND).cast("uchar")
      white.bandjoin(255).copy(interpretation: "srgb")
    end

    # libvips renders text as a single-band coverage mask; colorize it by using
    # the mask as the alpha channel over a solid fill, so it composites cleanly.
    # The string is escaped first because libvips parses it as Pango markup, so a
    # raw "&" or "<" in an account name would otherwise raise an invalid-markup error.
    def text(string, font, color)
      mask = Vips::Image.text(CGI.escapeHTML(string), font: font, width: WIDTH - 160, align: :centre)
      mask.new_from_image(color).bandjoin(mask).copy(interpretation: "srgb")
    end

    def display_name
      @account&.name.presence || Branding.app_name
    end
end
