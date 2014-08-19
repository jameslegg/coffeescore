https = require "https"
url = require "url"

settings =
    apiToken: ""
    roomId: 12345

urlbase = "https://api.hipchat.com/v2/"
lastMessageSeen = null  # ID of message last processed
currentCoffee = null  # Current coffee being ordered

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
            data = ''
            res.on 'data', (chunk) ->
                data += chunk
            res.on 'end', (chunk) ->
                console.log "response got"
                console.log data
                if data
                    obj = JSON.parse data
                else
                    obj = null
                handler obj

    req.write JSON.stringify body if body?
    req.end()

# Get recent messages from the room
getRecent = (not_before, handler) ->
    target = "/v2/room/" + settings.roomId + "/history/latest?auth_token=" + settings.apiToken
    target += '&not-before=' + not_before if not_before
    jsonRequest 'GET', target, null, handler

# Look to see if anyone is offering a coffee
checkForCoffees = (data) ->
    console.log "checkForCoffees"
    lastMessageSeen = data.items[data.items.length - 1].id
    for m in data.items
        console.log m.message
        continue if m.color  # Automated
        console.log "not automated"
        continue if m.id == lastMessageSeen
        console.log "not last message"
        if m.message.indexOf 'spare @coffee' < 0
            console.log "contains magic string"
            currentCoffee =
                requests: []
                offeredBy: m.from
            console.log "do coffee"
            console.log m.from
            postMessage "(coffee) @" + m.from.mention_name + " has a spare coffee. Reply '@coffee me' within the next three minutes if you'd like it", true
            setTimeout coffeeExpired, 1 * 60 * 1000  # FIXME make 3 mins
            return  # no more

# Look for people who want the coffee that is on offer
checkForRequests = (data) ->
    console.log "checkForRequests"
    lastMessageSeen = data.items[data.items.length - 1].id
    for m in data.items
        console.log m.message
        continue if m.color  # Automated
        console.log "not automated"
        continue if m.id == lastMessageSeen
        console.log "not last message"
        if m.message.indexOf '@coffee me' < 0
            console.log "contains magic string 2"
            currentCoffee.requests.push m.from

# The three minutes has expired, choose a winner
coffeeExpired = ->
    # Final sweep for any last-minute requests
    getRecent lastMessageSeen, checkForRequests

    if not currentCoffee.requests
        postMessage "(coffee) Aww, nobody wanted the lonely spare coffee", false
        return

    # Choose a winner FIXME not the first!
    winner = currentCoffee.requests[0]

    message = "(coffee) @" + winner.mention_name + " wins the coffee! ("
    message += winner.mention_name + " "  + userScore(winner.id, -1) + ", -1"
    message += "; " + currentCoffee.offeredBy.mention_name + " " + userScore(currentCoffee.offeredBy.id, +1) + ", +1"
    for user in currentCoffee.requests
        continue if user.id == winner.id
        message += "; " + user.mention_name + " "  + userScore(user.id, -1)
    message += ")"
    postMessage message, false

    # All done, no longer offering coffee, go back to poll
    currentCoffee = null

# Look up the score for user with ID <id> and alter it by <change> points.
userScore = (id, change) ->
    # FIXME
    return 0
    
# Main loop; get messages and either check for coffee offered or requested
pollBoard = ->
    console.log "pollBoard"
    console.log lastMessageSeen
    if currentCoffee
        handler = checkForRequests
    else
        handler = checkForCoffees
    getRecent lastMessageSeen, handler

# Send a message to HipChat
postMessage = (msg, notify) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.apiToken
    jsonRequest 'POST', target,
        message: msg
        notify: notify
        message_format: 'text'
        (data) ->
            if data
                console.log "Message send failed"
                console.log data

# Set the most recent message to avoid processing old content
getRecent null, (data) ->
    lastMessageSeen = data.items[data.items.length - 1].id
setInterval pollBoard, 20 * 1000  # 60 seconds
