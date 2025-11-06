class String
  def all_emoji?
    self.match? /\A(\p{Emoji_Presentation}|\p{Extended_Pictographic}|\uFE0F)+\z/u
  end
end
