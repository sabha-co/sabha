json.reactions @summary.groups do |group|
  json.content group.content
  json.count group.count
  json.boosters group.boosters do |booster|
    json.id booster.id
    json.name booster.name
  end
  json.truncated group.truncated
end
json.total @summary.total
json.truncated @summary.truncated
