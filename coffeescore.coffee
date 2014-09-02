async = require "async"
https = require "https"
sqlite = require("sqlite3")
url = require "url"

settings =
    postAPIToken: ""
    readAPIToken: ""
    roomId: 12345

urlbase = "https://api.hipchat.com/v2/"
lastMessageSeen = null  # ID of message last processed
currentCoffee = null  # Current coffee being ordered
db = new sqlite.Database "coffeescore.db"

# Make an HTTP request of type <method> to path <path> on the HipChat server.
# If <body> is supplied it will be posted as part of the request. Once the
# response is complete, <handler> will be called with the JSON-parsed
# response text
jsonRequest = (method, path, body, handler) ->
    opts =
        method: method
        hostname: "api.hipchat.com"
        path: path
    if body?
        opts.headers =
            "Content-Type": "application/json"
    req = https.request opts, (res) ->
            data = ""
            res.on "data", (chunk) ->
                data += chunk
            res.on "end", (chunk) ->
                if data
                    obj = JSON.parse data
                else
                    obj = null
                handler obj

    req.write JSON.stringify body if body?
    req.end()

# Get recent messages from the room
getRecent = (notBefore, handler) ->
    target = "/v2/room/" + settings.roomId + "/history/latest?auth_token=" + settings.readAPIToken
    target += "&not-before=" + notBefore if notBefore
    jsonRequest "GET", target, null, handler

# Look to see if anyone is offering a coffee
checkForCoffees = (data) ->
    for m in data.items
        continue if m.color  # Automated
        continue if m.id == lastMessageSeen
        if m.message.indexOf("spare @coffee") >= 0 or m.message.indexOf("/coff") >= 0
            currentCoffee =
                requests: []
                offeredBy: m.from
            postMessage "@" + m.from.mention_name + " has a spare coffee. Reply '@coffee me' within the next three minutes if you'd like it", true
            lastMessageSeen = m.id
            setTimeout coffeeExpired, 3 * 60 * 1000
            return  # no more
    lastMessageSeen = data.items[data.items.length - 1].id

# Look for people who want the coffee that is on offer
checkForRequests = (data) ->
    for m in data.items
        continue if m.color  # Automated
        continue if m.id == lastMessageSeen
        if m.message.indexOf("@coffee me") >= 0 or m.message.indexOf('/yes') >=0
            currentCoffee.requests.push m.from
    lastMessageSeen = data.items[data.items.length - 1].id

# The three minutes has expired, choose a winner
coffeeExpired = ->
    # Final sweep for any last-minute requests
    getRecent lastMessageSeen, (data) ->
        checkForRequests(data)
        messageWinner()

messageWinner = ->
    if currentCoffee.requests.length == 0
        currentCoffee = null
        postMessage "Aww, nobody wanted the lonely spare coffee", false
        return

    # Get all scores
    lookups = {}
    for user in currentCoffee.requests
        u = user
        lookups[u.id] = (callback) ->
            userScore u, 0, (err, data) ->
                callback err, data["score"]

    async.parallel lookups, (err, scores) ->

        winner = [null, Number.NEGATIVE_INFINITY]
        # Earliest wins, so walk in order
        for u in currentCoffee.requests
            score = scores[u.id]
            u.score = score
            if score > winner[1]
                winner = [u, score]

        doScores = () ->
            message = "@" + winner.mention_name + " wins the spare coffee of @" + currentCoffee.offeredBy.mention_name + "! ("
            message += winner.mention_name + " "  + winner.score + ", -1"
            message += "; " + currentCoffee.offeredBy.mention_name + " " + currentCoffee.offeredBy.score + ", +1"
            for user in currentCoffee.requests
                continue if user.id == winner.id
                message += "; " + user.mention_name + " "  + user.score
            message += ")"
            postMessage message, false

            # All done, no longer offering coffee, go back to poll
            currentCoffee = null

        winner = winner[0]
        if winner.id != currentCoffee.offeredBy.id
            winner_id = winner.id
            offer_id = currentCoffee.offeredBy.id
            handlers = {}
            handlers[winner_id] = (callback) ->
                userScore winner, -1, (err, data) ->
                    callback err, data["score"]
            handlers[offer_id] = (callback) ->
                userScore currentCoffee.offeredBy, +1, (err, data) ->
                    callback err, data["score"]

            async.parallel handlers, (err, data) ->
                winner.score = data[winner_id]
                currentCoffee.offeredBy.score = data[offer_id]
                doScores()
        else
            currentCoffee.offeredBy.score = winner.score
            doScores()

# Look up the score for user with ID <id> and alter it by <change> points.
userScore = (user, change, callback) ->
    # We'll do this last
    lookup_fn = (err, data) ->
        callback err, data if err
        db.get "SELECT name, score FROM scores WHERE user_id = ?", [user.id], callback

    # If change, do a second-level step of updating, otherwise go direct to last step
    if change
        next_step = (err, data) ->
            lookup_fn err, data if err
            db.run "UPDATE scores SET name = ?, score = score + ? WHERE user_id = ?", [user.mention_name, change, user.id], lookup_fn
    else
        next_step = lookup_fn

    # First step ensures we have a row; does whatever the next step does
    db.run "INSERT OR IGNORE INTO scores (user_id, name) VALUES (?, ?)", [user.id, user.mention_name], next_step

# Main loop; get messages and either check for coffee offered or requested
pollBoard = ->
    if currentCoffee
        handler = checkForRequests
    else
        handler = checkForCoffees
    getRecent lastMessageSeen, handler

# Send a message to HipChat
postMessage = (msg, notify) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.postAPIToken
    jsonRequest "POST", target,
        message: msg
        notify: notify
        message_format: "text"
        color: "red"
        (data) ->

# Set the most recent message to avoid processing old content
db.run """
    CREATE TABLE IF NOT EXISTS scores (
        user_id INT NOT NULL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        score INT NOT NULL DEFAULT 0
    )
""", [], ->
    getRecent null, (data) ->
        lastMessageSeen = data.items[data.items.length - 1].id
        setInterval pollBoard, 15 * 1000  # 15 seconds
