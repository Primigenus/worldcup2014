


Meteor.startup ->
	Meteor.call "getDate", (err, res) -> Session.setDefault("date", res)
	Meteor.setInterval ->
		Meteor.call "getDate", (err, res) -> Session.set("date", res)
	, 1000

Template.groups.group = -> Groups.find()
Template.groups.match = -> Matches.find type: @letter

# todo: we can calculate this based on match score predictions
Template.groups.winner1_prediction = ->
	return unless Meteor.user()
	Teams.findOne(_id: Meteor.user().profile.predictions?[@_id]?.winner1)?.name or "nobody"
Template.groups.winner2_prediction = ->
	return unless Meteor.user()
	Teams.findOne(_id: Meteor.user().profile.predictions?[@_id]?.winner2)?.name or "nobody"




Template.matchRow.isCurrentMatch = ->
	now = Session.get("date")
	before = new Date(now - 1000 * 60 * 120)
	if @date <= now and @date >= before then "current" else ""
Template.matchRow.disabled = -> if @date < Session.get("date") then "disabled" else ""
Template.matchRow.date  = -> moment(@date).format("DD MMM")
Template.matchRow.time  = ->
	time = moment(@date).format("HH:mm")
	time
Template.matchRow.team1 = -> Teams.findOne(_id: @team1)?.name
Template.matchRow.team1code = -> Teams.findOne(_id: @team1)?.code.toUpperCase()
Template.matchRow.team2 = -> Teams.findOne(_id: @team2)?.name
Template.matchRow.team2code = -> Teams.findOne(_id: @team2)?.code.toUpperCase()
Template.matchRow.team1goals_prediction = ->
	return unless Meteor.user()
	Meteor.user().profile.predictions?[@_id]?.team1goals
Template.matchRow.team2goals_prediction = ->
	return unless Meteor.user()
	Meteor.user().profile.predictions?[@_id]?.team2goals

Template.matchRow.events
	"input .score:not(.prediction) input": (evt) ->
		field = $(evt.target).data("field")
		value = $(evt.target).val()
		Meteor.call "updateScore", @_id, field, value

	"input .prediction input": (evt) ->
		return unless Meteor.user()

		field = $(evt.target).data("field")
		value = $(evt.target).val()

		Meteor.call "updatePredictions", @_id, @type, field, value



Template.leaderboard.person = -> Meteor.users.find({}, sort: "profile.points": -1)
Template.leaderboard.name = -> @services.google.given_name
Template.leaderboard.points = -> @profile.points or 0




# there is a current match if one started between now and 2 hours ago
Template.currentMatch.match = ->
	now = Session.get("date")
	before = new Date(now - 1000 * 60 * 120)
	Matches.findOne $and: [{date: $lte: now}, {date: $gte: before}]
# it's halftime if the match started between 45 and 60 mins ago
Template.currentMatch.team1 = -> Teams.findOne(_id: @team1).name
Template.currentMatch.team2 = -> Teams.findOne(_id: @team2).name
Template.currentMatch.time = ->
	time = moment(Session.get("date") - @date)
	if time > 1000 * 60 * 45 and time < 1000 * 60 * 60
		return "halftime!"
	time.format "mm:ss"

Template.currentMatch.nextMatch = -> Matches.findOne({date: $gte: new Date()}, {sort: date: 1})
Template.currentMatch.nextTeam1 = ->
	teamId = Matches.findOne({date: $gte: new Date()}, {sort: date: 1}).team1
	Teams.findOne(_id: teamId).name if teamId
Template.currentMatch.nextTeam2 = ->
	teamId = Matches.findOne({date: $gte: new Date()}, {sort: date: 1}).team2
	Teams.findOne(_id: teamId).name if teamId
Template.currentMatch.nextTime = -> # gadget, next time...
	moment(Matches.findOne({date: $gte: new Date()}, {sort: date: 1}).date).format "dddd, MMMM DD\\t\\h \\a\\t HH:mm"

Template.currentMatch.events
	input: (evt) ->
		updateObj = {}
		field = $(evt.target).data("field")
		value = $(evt.target).val()
		updateObj[field] = value
		Matches.update @_id, $set: updateObj