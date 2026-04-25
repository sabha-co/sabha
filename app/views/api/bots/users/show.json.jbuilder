json.partial! "api/bots/users/user", user: @user
json.bio           @user.bio
json.twitter_url   @user.twitter_url
json.linkedin_url  @user.linkedin_url
json.personal_url  @user.personal_url
