module Message::Answerable
  extend ActiveSupport::Concern

  included do
    belongs_to :answered_by, class_name: "User", optional: true
  end

  def answered?
    answered_at.present? && answered_by.present?
  end

  def answered_by_user?(user)
    answered? && answered_by == user
  end

  def answer_by(user)
    return false if answered?

    update(answered_at: Time.current, answered_by: user)
  end

  def undo_answer_by(user)
    return false unless answered_by_user?(user)

    update(answered_at: nil, answered_by: nil)
  end
end
