@Teams   = new Meteor.Collection "teams"
@Matches = new Meteor.Collection "matches"
@Groups  = new Meteor.Collection "groups"

if Meteor.isClient

	Meteor.startup ->
		Meteor.call "getDate", (err, res) -> Session.setDefault("date", res)
		Meteor.setInterval ->
			Meteor.call "getDate", (err, res) -> Session.set("date", res)
		, 1000

	Meteor.users.after.update (userId, doc, fieldNames, modifier, options) ->
		return unless userId

		points = 0
		for matchId, goals of doc.profile.predictions
			match = Matches.findOne(matchId)

			# correct prediction: worth 1 point
			if match?.date < new Date() and match?.team1goals is goals.team1goals and match?.team2goals is goals.team2goals
				points = points + 1

		if points isnt this.previous.profile.points
			Meteor.users.update userId, $set: "profile.points": points

	Template.groups.group = -> Groups.find()
	Template.groups.match = -> Matches.find type: @letter

	# todo: we can calculate this based on match score predictions
	Template.groups.winner1_prediction = ->
		return unless Meteor.user()
		Teams.findOne(_id: Meteor.user().profile.predictions[@_id]?.winner1)?.name or "nobody"
	Template.groups.winner2_prediction = ->
		return unless Meteor.user()
		Teams.findOne(_id: Meteor.user().profile.predictions[@_id]?.winner2)?.name or "nobody"




	Template.matchRow.isCurrentMatch = ->
		now = Session.get("date")
		before = new Date(now - 1000 * 60 * 120)
		if @date <= now and @date >= before then "current" else ""
	Template.matchRow.date  = -> moment(@date).format("DD MMM")
	Template.matchRow.time  = ->
		time = moment(@date).format("HH:mm")
		time
	Template.matchRow.team1 = -> Teams.findOne(_id: @team1)?.name
	Template.matchRow.team2 = -> Teams.findOne(_id: @team2)?.name
	Template.matchRow.team1goals_prediction = ->
		return unless Meteor.user()
		Meteor.user().profile.predictions[@_id]?.team1goals
	Template.matchRow.team2goals_prediction = ->
		return unless Meteor.user()
		Meteor.user().profile.predictions[@_id]?.team2goals

	Template.matchRow.events
		"input .score:not(.prediction) input": (evt) ->
			updateObj = {}
			field = $(evt.target).data("field")
			value = $(evt.target).val()
			updateObj[field] = value
			Matches.update @_id, $set: updateObj

		"input .prediction input": (evt) ->
			return unless Meteor.user()

			updateObj = {}
			field = $(evt.target).data("field")
			value = $(evt.target).val()
			updateObj["profile.predictions.#{@_id}.#{field}"] = value

			matchesInGroup = Matches.find(type: @type).fetch()
			predictedGroupRanking = {}
			for match in matchesInGroup
				predictedGoals = Meteor.user().profile.predictions[match._id]
				predictedGoals = {team1goals: 0, team2goals: 0} unless predictedGoals

				if predictedGoals.team1goals > predictedGoals.team2goals
					if predictedGroupRanking[match.team1]
						predictedGroupRanking[match.team1] += 3
					else
						predictedGroupRanking[match.team1] = 3
				else if predictedGoals.team1goals is predictedGoals.team2goals
					if predictedGroupRanking[match.team1]
						predictedGroupRanking[match.team1] += 1
					else
						predictedGroupRanking[match.team1] = 1
					if predictedGroupRanking[match.team2]
						predictedGroupRanking[match.team2] += 1
					else
						predictedGroupRanking[match.team2] = 1
				else
					if predictedGroupRanking[match.team2]
						predictedGroupRanking[match.team2] += 3
					else
						predictedGroupRanking[match.team2] = 3

			predictedGroupRanking = _.object(_.pairs(predictedGroupRanking).sort((a, b) -> return -(a[1] - b[1])))
			
			groupId = Groups.findOne(letter: @type)._id
			updateObj["profile.predictions.#{groupId}.winner1"] = _.keys(predictedGroupRanking)[0]
			updateObj["profile.predictions.#{groupId}.winner2"] = _.keys(predictedGroupRanking)[1]

			Meteor.users.update Meteor.userId(), $set: updateObj



	Template.leaderboard.person = -> Meteor.users.find({}, sort: points: -1)
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


if Meteor.isServer

	Meteor.methods
		getDate: -> new Date()

	Meteor.users.allow
		update: (userId, doc, fieldNames, modifier) ->
			return no unless userId
			yes

	Meteor.startup ->

		#Teams.remove {}
		#Matches.remove {}
		#Groups.remove {}

		if Teams.find().count() is 0

			teams = [{"name":"Algeria","code":"alg"},{"name":"Cameroon","code":"cmr"}, {"name":"Côte d'Ivoire","code":"civ"},{"name":"Ghana","code":"gha"},{"name":"Nigeria","code":"nga"},{"name":"Australia","code":"aus"},{"name":"Iran","code":"irn"},{"name":"Japan","code":"jpn"},{"name":"Korea Republic","code":"kor"},{"name":"Belgium","code":"bel"},{"name":"Bosnia and Herzegovina","code":"bih"},{"name":"Croatia","code":"cro"},{"name":"England","code":"eng"},{"name":"France","code":"fra"},{"name":"Germany","code":"ger"},{"name":"Greece","code":"gre"},{"name":"Italy","code":"ita"},{"name":"Netherlands","code":"ned"},{"name":"Portugal","code":"por"},{"name":"Russia","code":"rus"},{"name":"Spain","code":"esp"},{"name":"Switzerland","code":"sui"},{"name":"Costa Rica","code":"crc"},{"name":"Honduras","code":"hon"},{"name":"Mexico","code":"mex"},{"name":"USA","code":"usa"},{"name":"Argentina","code":"arg"},{"name":"Brazil","code":"bra"},{"name":"Chile","code":"chi"},{"name":"Colombia","code":"col"},{"name":"Ecuador","code":"ecu"},{"name":"Uruguay","code":"uru"}]

			_.each teams, (t) -> Teams.insert t

		if Matches.find().count() is 0

			A = (type, date, time, team1, team2) ->
				Matches.insert
					type: type
					date: new Date(date + " 2014 " + time + ":00")
					team1: Teams.findOne(code: team1)?._id or team1
					team2: Teams.findOne(code: team2)?._id or team2
					team1goals: 0
					team2goals: 0

			# Group A
			A "A", "6/12", 22, "bra", "cro"
			A "A", "6/13", 18, "mex", "cmr"
			A "A", "6/17", 21, "bra", "mex"
			A "A", "6/19",  0, "cmr", "cro"
			A "A", "6/23", 22, "cmr", "bra"
			A "A", "6/23", 22, "cro", "mex"
			# Group B
			A "B", "6/13", 21, "esp", "ned"
			A "B", "6/14",  0, "chi", "aus"
			A "B", "6/18", 18, "aus", "ned"
			A "B", "6/18", 21, "aus", "esp"
			A "B", "6/23", 18, "aus", "esp"
			A "B", "6/23", 18, "ned", "chi"
			# Group C
			A "C", "6/14", 18, "col", "gre"
			A "C", "6/15",  3, "civ", "jpn"
			A "C", "6/19", 18, "col", "civ"
			A "C", "6/20",  0, "jpn", "gre"
			A "C", "6/24", 22, "jpn", "col"
			A "C", "6/24", 22, "gre", "civ"
			# Group D
			A "D", "6/14", 21, "uru", "crc"
			A "D", "6/15",  0, "eng", "ita"
			A "D", "6/19", 21, "uru", "eng"
			A "D", "6/20", 18, "ita", "crc"
			A "D", "6/24", 18, "ita", "uru"
			A "D", "6/24", 18, "crc", "eng"
			# Group E
			A "E", "6/15", 18, "sui", "ecu"
			A "E", "6/15", 21, "fra", "hon"
			A "E", "6/20", 21, "sui", "fra"
			A "E", "6/21",  0, "hon", "ecu"
			A "E", "6/25", 22, "hon", "sui"
			A "E", "6/25", 22, "ecu", "fra"
			# Group F
			A "F", "6/16",  0, "arg", "bih"
			A "F", "6/16", 21, "irn", "nga"
			A "F", "6/21", 18, "arg", "irn"
			A "F", "6/22",  0, "nga", "bih"
			A "F", "6/25", 18, "nga", "arg"
			A "F", "6/25", 18, "bih", "irn"
			# Group G
			A "G", "6/16", 18, "ger", "por"
			A "G", "6/17",  0, "gha", "usa"
			A "G", "6/21", 21, "ger", "gha"
			A "G", "6/23",  0, "usa", "por"
			A "G", "6/26", 18, "usa", "ger"
			A "G", "6/26", 18, "por", "gha"
			# Group H
			A "H", "6/17", 18, "bel", "alg"
			A "H", "6/18",  0, "rus", "kor"
			A "H", "6/22", 18, "bel", "rus"
			A "H", "6/22", 21, "kor", "alg"
			A "H", "6/26", 22, "kor", "bel"
			A "H", "6/26", 22, "alg", "rus"
			# 1/8 Finals
			A "1/8", "6/28", 18, "1A", "2B"
			A "1/8", "6/28", 22, "1C", "2D"
			A "1/8", "6/29", 18, "1B", "2A"
			A "1/8", "6/29", 22, "1D", "2C"
			A "1/8", "6/30", 18, "1E", "2F"
			A "1/8", "6/30", 22, "1G", "2H"
			A "1/8", "7/1" , 18, "1F", "2E"
			A "1/8", "7/1" , 22, "1H", "2G"
			# 1/4 Finals
			A "1/4", "7/4" , 18, "5" , "6"
			A "1/4", "7/4" , 22, "1" , "2"
			A "1/4", "7/5" , 18, "7" , "8"
			A "1/4", "7/5" , 22, "3" , "4"
			# 1/2 Finals
			A "1/2", "7/8" , 22, "B" , "A"
			A "1/2", "7/9" , 22, "D" , "C"
			# 3/4th place
			A "3/4", "7/12", 22, "YL", "ZL"
			# Final
			A "1/1", "7/13", 21, "YW", "ZW"

		if Groups.find().count() is 0

			addGroup = (letter, teams) -> Groups.insert letter: letter, first: null, second: null, teams: teams

			addGroup "A", ["bra", "cro", "mex", "cmr"]
			addGroup "B", ["esp", "chi", "ned", "aus"]
			addGroup "C", ["col", "gre", "jpn", "civ"]
			addGroup "D", ["uru", "eng", "ita", "crc"]
			addGroup "E", ["sui", "fra", "ecu", "hon"]
			addGroup "F", ["arg", "bih", "irn", "nga"]
			addGroup "G", ["ger", "gha", "usa", "por"]
			addGroup "H", ["bel", "alg", "rus", "kor"]