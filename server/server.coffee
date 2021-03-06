Kadira.connect('pmgzKB7ZJLazunxCz', '68653150-de49-4483-bb8d-9c9a8c31a098')

Meteor.startup ->
	Meteor.setInterval ->
		now = new Date()
		before = new Date(now - 1000 * 60 * 120)
		currentMatch = Matches.findOne $and: [{date: $lte: now}, {date: $gte: before}]

		if currentMatch
			HTTP.get "http://worldcup.sfg.io/matches/current", (err, res) ->
				if res?.data.length
					Matches.update currentMatch._id, {
						$set:
							team1goals: res.data[0].home_team.goals,
							team2goals: res.data[0].away_team.goals,
							winnerOnPenalties: null
					}
	, 10000

	if Facts.find().count() is 0
		Facts.insert
			numYellowCards: 0
			numRedCards: 0
			numGoals: 0
			topScorer: null

	Meteor.setInterval ->
		HTTP.get "http://worldcup.sfg.io/matches", (err, res) ->
			if res?.data?.length
				types = ["goal", "goal-own", "goal-penalty", "red-card", "yellow-card"]

				interestingEvents = _.reduce res.data, ((memo, match) ->
					events = match.home_team_events.concat(match.away_team_events)
					events = _.filter events, (e) -> e.type_of_event in types
					memo.concat(events)
				), []

				getTotal = (type) -> _.reduce interestingEvents, ((memo, event) ->
					if event.type_of_event is type
						return memo + 1
					memo
				), 0

				scorers = _.countBy interestingEvents, (event) ->
					event.player if event.type_of_event in ["goal", "goal-own", "goal-penalty"]
				scorers = _.pairs(scorers).sort((a, b) -> -(a[1] - b[1]))
				scorers = _.reject scorers, (scorer) -> scorer[0] is "undefined"
				topScorer = scorers[0][0]

				Facts.upsert Facts.findOne()._id, $set: {
					numYellowCards: getTotal("yellow-card")
					numRedCards: getTotal("red-card")
					numGoals: getTotal("goal") + getTotal("goal-penalty") + getTotal("goal-own")
					topScorer: topScorer
				}
	, 10000

	Meteor.users.after.update (userId, doc, fieldNames, modifier, options) ->
		return unless userId
		return unless _.keys(modifier["$set"])[0].indexOf("profile.predictions") is 0
		allMatches = Matches.find(date: $lt: new Date()).fetch()
		points = recalcPoints doc, allMatches
		if points isnt this.previous.profile.points
			Meteor.users.update userId, $set: "profile.points": points

	Matches.after.update (userId, doc, fieldNames, modifier, options) ->
		allMatches = Matches.find(date: $lt: new Date()).fetch()
		_.each Meteor.users.find().fetch(), (user) ->
			points = recalcPoints user, allMatches
			if points isnt user.profile.points
				Meteor.users.update user._id, $set: "profile.points": points

Meteor.users.allow
	update: (userId, doc, fieldNames, modifier) ->
		return yes if userId is "zWCoNBk9TL6c8mxZG" # rahul@q42.nl
		return no unless userId
		return no if userId isnt doc._id
		yes

Accounts.config
	restrictCreationByEmailDomain: 'q42.nl'

Accounts.onCreateUser (options, user) ->
	if options.profile
		options.profile.predictions = {}
		user.profile = options.profile
	user

recalcPoints = (user, matches) ->
	return unless user
	points = 0
	for matchId, predictions of user.profile.predictions
		match = _.find(matches, (m) -> m._id is matchId)
		continue unless match
		
		aTeam1Goals = parseInt(match.team1goals)
		aTeam2Goals = parseInt(match.team2goals)
		pTeam1Goals = parseInt(predictions.team1goals)
		pTeam2Goals = parseInt(predictions.team2goals)

		# predict number of goals left = 1 point
		# predict number of goals right = 1 point
		points++ if aTeam1Goals is pTeam1Goals
		points++ if aTeam2Goals is pTeam2Goals
				
		actualWinner = null
		if match.team1goals > match.team2goals
			actualWinner = match.team1
		else if match.team2goals > match.team1goals
			actualWinner = match.team2
		else if match.team1goals is match.team2goals
			if match.type in ["1/8", "1/4", "1/2", "3/4", "1/1"]
				actualWinner = match.winnerOnPenalties

		predictedWinner = null
		if predictions.team1goals > predictions.team2goals
			predictedWinner = match.team1
		else if predictions.team2goals > predictions.team1goals
			predictedWinner = match.team2
		else if predictions.team1goals is predictions.team2goals
			if match.type in ["1/8", "1/4", "1/2", "3/4", "1/1"]
				predictedWinner = predictions.predictedWinner

		# predict winner = 3 points
		if actualWinner is predictedWinner
			points += 3


	# todo: predict world cup winner:     +50

	facts = Facts.findOne()
	points += 25 if parseInt(user.profile.predictions.numRedCards) is facts.numRedCards
	points += 25 if parseInt(user.profile.predictions.numYellowCards) is facts.numYellowCards
	points += 25 if parseInt(user.profile.predictions.numGoals) is facts.numGoals
	points += 25 if user.profile.predictions.mostGoals is facts.topScorer

	# todo: user can predict who plays in which final
	# more: https://docs.google.com/a/q42.nl/document/d/1kxvBSlTZ9Mjbd6F-alhszRAyak5CWG2u-FuCeZc_XBg/edit

	points

calcRanking = (type) ->
	matchesInGroup = Matches.find(type: type).fetch()
	groupRanking = {}
	for match in matchesInGroup
		if match.team1goals > match.team2goals
			if groupRanking[match.team1]
				groupRanking[match.team1] += 3
			else
				groupRanking[match.team1] = 3
		else if match.team1goals is match.team2goals
			if groupRanking[match.team1]
				groupRanking[match.team1] += 1
			else
				groupRanking[match.team1] = 1
			if groupRanking[match.team2]
				groupRanking[match.team2] += 1
			else
				groupRanking[match.team2] = 1
		else
			if groupRanking[match.team2]
				groupRanking[match.team2] += 3
			else
				groupRanking[match.team2] = 3

	_.object(_.pairs(groupRanking).sort((a, b) -> -(a[1] - b[1])))

getPredictedGroupRanking = (type) ->
	matchesInGroup = Matches.find(type: type).fetch()
	predictedGroupRanking = {}
	for match in matchesInGroup
		predictedGoals = Meteor.user().profile.predictions?[match._id]
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

	_.object(_.pairs(predictedGroupRanking).sort((a, b) -> return -(a[1] - b[1])))

getPredictedTeam = (type, matchNum) ->
	predictions = Meteor.user().profile.predictions
	if type is "1/4"
		eighthFinals = Matches.find({type: "1/8"}, {sort: date: 1}).fetch()
		match = eighthFinals[matchNum]
		matchPredictions = predictions[match._id]
		
	if type is "1/2"
		quarterFinals = Matches.find({type: "1/4"}, {sort: date: 1}).fetch()
		match = quarterFinals[matchNum]
		matchPredictions = predictions[match._id]

	# if type is "3/4"
	# 	semiFinals = Matches.find({type: "1/2"}, {sort: date: 1}).fetch()
	# 	match = semiFinals[matchNum - 1]
	# 	matchPredictions = predictions[match._id]

	# if type is "1/1"
	# 	semiFinals = Matches.find({type: "1/2"}, {sort: date: 1}).fetch()
	# 	match = semiFinals[matchNum - 1]
	# 	matchPredictions = predictions[match._id]

	if matchPredictions.team1goals > matchPredictions.team2goals
		return match.team1
	else if matchPredictions.team1goals is matchPredictions.team2goals
		return matchPredictions.predictedWinner
	return match.team2

Meteor.methods
	getDate: -> new Date()

	setMatchTeams: (matchId, newTeam1, newTeam2) ->
		Matches.update matchId, $set: team1: Teams.findOne(code: newTeam1)._id, team2: Teams.findOne(code: newTeam2)._id

	updatePredictionDetails: (field, value) ->
		return unless @userId
		updateObj = {}
		updateObj["profile.predictions.#{field}"] = value
		Meteor.users.update @userId, $set: updateObj

	calcRankings: ->
		# letters = "ABCDEFGH".split("")
		# rankings = []
		# _.each letters, (letter, n) ->
		# 	rankings.push calcRanking(letters[n])

		semiFinals = Matches.find({type: "1/2"}, sort: date: 1).fetch()

		# B vs A
		Matches.update(semiFinals[0]._id, {$set: {
			team1: getPredictedTeam("1/2", 1)
			team2: getPredictedTeam("1/2", 0)
		}})
		# D vs C
		Matches.update(semiFinals[1]._id, {$set: {
			team1: getPredictedTeam("1/2", 3)
			team2: getPredictedTeam("1/2", 2)
		}})

		# quarterFinals = Matches.find({type: "1/4"}, {sort: date: 1}).fetch()

		# # 5 vs 6
		# Matches.update(quarterFinals[0]._id, {$set: {
		# 	team1: getPredictedTeam("1/4", 5)
		# 	team2: getPredictedTeam("1/4", 6)
		# }})
		# # 1 vs 2
		# Matches.update(quarterFinals[1]._id, {$set: {
		# 	team1: getPredictedTeam("1/4", 1)
		# 	team2: getPredictedTeam("1/4", 2)
		# }})
		# # 7 vs 8
		# Matches.update(quarterFinals[2]._id, {$set: {
		# 	team1: getPredictedTeam("1/4", 7)
		# 	team2: getPredictedTeam("1/4", 8)
		# }})
		# # 3 vs 4
		# Matches.update(quarterFinals[3]._id, {$set: {
		# 	team1: getPredictedTeam("1/4", 3)
		# 	team2: getPredictedTeam("1/4", 4)
		# }})

		# 1A vs 2B
		# Matches.update(eighthFinals[0]._id, {$set: {team1: _.keys(rankings[0])[0], team2: _.keys(rankings[1])[1]}})
		# # 1C vs 2D
		# Matches.update(eighthFinals[1]._id, {$set: {team1: _.keys(rankings[2])[0], team2: _.keys(rankings[3])[1]}})
		# # 1B vs 2A
		# Matches.update(eighthFinals[2]._id, {$set: {team1: _.keys(rankings[1])[0], team2: _.keys(rankings[0])[1]}})
		# # 1D vs 2C
		# Matches.update(eighthFinals[3]._id, {$set: {team1: _.keys(rankings[3])[0], team2: _.keys(rankings[2])[1]}})
		# # 1E vs 2F
		# Matches.update(eighthFinals[4]._id, {$set: {team1: _.keys(rankings[4])[0], team2: _.keys(rankings[5])[1]}})
		# # 1G vs 2H
		# Matches.update(eighthFinals[5]._id, {$set: {team1: _.keys(rankings[6])[0], team2: _.keys(rankings[7])[1]}})
		# # 1F vs 2E
		# Matches.update(eighthFinals[6]._id, {$set: {team1: _.keys(rankings[5])[0], team2: _.keys(rankings[4])[1]}})
		# # 1H vs 2G
		# Matches.update(eighthFinals[7]._id, {$set: {team1: _.keys(rankings[7])[0], team2: _.keys(rankings[6])[1]}})

	updateScore: (id, field, value) ->
		return unless @userId
		updateObj = {}
		updateObj[field] = value
		Matches.update id, $set: updateObj

	updateFinalsWinner: (id, teamId) ->
		return unless @userId

		updateObj = {}
		updateObj["profile.predictions.#{id}.predictedWinner"] = teamId

		Meteor.users.update @userId, $set: updateObj

	updatePredictions: (id, type, field, value) ->
		return unless @userId

		updateObj = {}
		updateObj["profile.predictions.#{id}.#{field}"] = value
		
		groupId = Groups.findOne(letter: type)?._id
		if groupId
			predictedGroupRanking = getPredictedGroupRanking type
			updateObj["profile.predictions.#{groupId}.winner1"] = _.keys(predictedGroupRanking)[0]
			updateObj["profile.predictions.#{groupId}.winner2"] = _.keys(predictedGroupRanking)[1]

		Meteor.users.update @userId, $set: updateObj

	insertTeams: ->

		Teams.remove({})

		teams = [{"name":"Algeria","code":"alg"},{"name":"Cameroon","code":"cmr"}, {"name":"Côte d'Ivoire","code":"civ"},{"name":"Ghana","code":"gha"},{"name":"Nigeria","code":"nga"},{"name":"Australia","code":"aus"},{"name":"Iran","code":"irn"},{"name":"Japan","code":"jpn"},{"name":"Korea Republic","code":"kor"},{"name":"Belgium","code":"bel"},{"name":"Bosnia and Herzegovina","code":"bih"},{"name":"Croatia","code":"cro"},{"name":"England","code":"eng"},{"name":"France","code":"fra"},{"name":"Germany","code":"ger"},{"name":"Greece","code":"gre"},{"name":"Italy","code":"ita"},{"name":"Netherlands","code":"ned"},{"name":"Portugal","code":"por"},{"name":"Russia","code":"rus"},{"name":"Spain","code":"esp"},{"name":"Switzerland","code":"sui"},{"name":"Costa Rica","code":"crc"},{"name":"Honduras","code":"hon"},{"name":"Mexico","code":"mex"},{"name":"USA","code":"usa"},{"name":"Argentina","code":"arg"},{"name":"Brazil","code":"bra"},{"name":"Chile","code":"chi"},{"name":"Colombia","code":"col"},{"name":"Ecuador","code":"ecu"},{"name":"Uruguay","code":"uru"}]

		_.each teams, (t) -> Teams.insert t

	insertMatches: ->

		Matches.remove({})

		A = (type, date, time, team1, team2, team1goals, team2goals) ->
			Matches.insert
				type: type
				date: new Date("2014/" + date + " " + time + ":00+0200")
				team1: Teams.findOne(code: team1)?._id or team1
				team2: Teams.findOne(code: team2)?._id or team2
				team1goals: team1goals or 0
				team2goals: team2goals or 0

		# Group A
		A "A", "6/12", 22, "bra", "cro", 3, 1
		A "A", "6/13", 18, "mex", "cmr", 1, 0
		A "A", "6/17", 21, "bra", "mex"
		A "A", "6/19",  0, "cmr", "cro"
		A "A", "6/23", 22, "cmr", "bra"
		A "A", "6/23", 22, "cro", "mex"
		# Group B
		A "B", "6/13", 21, "esp", "ned", 1, 5
		A "B", "6/14",  0, "chi", "aus", 3, 1
		A "B", "6/18", 18, "aus", "ned"
		A "B", "6/18", 21, "esp", "chi"
		A "B", "6/23", 18, "aus", "esp"
		A "B", "6/23", 18, "ned", "chi"
		# Group C
		A "C", "6/14", 18, "col", "gre", 3, 0
		A "C", "6/15",  3, "civ", "jpn", 2, 1
		A "C", "6/19", 18, "col", "civ"
		A "C", "6/20",  0, "jpn", "gre"
		A "C", "6/24", 22, "jpn", "col"
		A "C", "6/24", 22, "gre", "civ"
		# Group D
		A "D", "6/14", 21, "uru", "crc", 1, 3
		A "D", "6/15",  0, "eng", "ita", 1, 2
		A "D", "6/19", 21, "uru", "eng"
		A "D", "6/20", 18, "ita", "crc"
		A "D", "6/24", 18, "ita", "uru"
		A "D", "6/24", 18, "crc", "eng"
		# Group E
		A "E", "6/15", 18, "sui", "ecu", 2, 1
		A "E", "6/15", 21, "fra", "hon", 3, 0
		A "E", "6/20", 21, "sui", "fra"
		A "E", "6/21",  0, "hon", "ecu"
		A "E", "6/25", 22, "hon", "sui"
		A "E", "6/25", 22, "ecu", "fra"
		# Group F
		A "F", "6/16",  0, "arg", "bih", 2, 1
		A "F", "6/16", 21, "irn", "nga"
		A "F", "6/21", 18, "arg", "irn"
		A "F", "6/22",  0, "nga", "bih"
		A "F", "6/25", 18, "nga", "arg"
		A "F", "6/25", 18, "bih", "irn"
		# Group G
		A "G", "6/16", 18, "ger", "por", 4, 0
		A "G", "6/17",  0, "gha", "usa", 1, 2
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

	insertGroups: ->

		Groups.find({})

		addGroup = (letter, teams) -> Groups.insert letter: letter, first: null, second: null, teams: teams

		addGroup "A", ["bra", "cro", "mex", "cmr"]
		addGroup "B", ["esp", "chi", "ned", "aus"]
		addGroup "C", ["col", "gre", "jpn", "civ"]
		addGroup "D", ["uru", "eng", "ita", "crc"]
		addGroup "E", ["sui", "fra", "ecu", "hon"]
		addGroup "F", ["arg", "bih", "irn", "nga"]
		addGroup "G", ["ger", "gha", "usa", "por"]
		addGroup "H", ["bel", "alg", "rus", "kor"]