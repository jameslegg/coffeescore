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
                if data
                    obj = JSON.parse data
                else
                    obj = null
                handler obj

    req.write JSON.stringify body if body?
    req.end()

# Get recent messages from the room
getRecent = (not_before, handler) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.apiToken
    target += '&not_before=' + not_before if not_before
    jsonRequest 'GET', targetURL, null, handler

# Look to see if anyone is offering a coffee
checkForCoffees = (data) ->
    for m in data.items
        if m.message.indexOf 'spare @coffee' < 0
            currentCoffee =
                offeredBy:
                    id: m.from.id
                    name: m.from.mention_name
            postMessage "@" + m.from.mention_name + " has a spare coffee. Reply '@coffee me' within the next three minutes if you'd like it", true
            setTimeout 3 * 60 * 1000, coffeeExpired

# Look for people who want the coffee that is on offer
checkForRequests = ->

# The three minutes has expired, choose a winner
coffeeExpired = ->
    # Final sweep for any last-minute requests
    getRecent lastMessageSeen, checkForRequests

    # All done, no longer offering coffee, go back to poll
    currentCoffee = null
    
# Main loop; get messages and either check for coffee offered or requested
pollBoard = ->
    handler = checkForRequests if currentCoffee else checkForCoffees
    getRecent lastMessageSeen, handler

# Send a message to HipChat
postMessage = (msg, notify) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.apiToken
    jsonRequest 'POST', target,
        message: msg
        notify: notify,
        (data) ->
            if data
                console.log "Message send failed"
                console.log data

# Set the most recent message to avoid processing old content
getRecent null, (data) ->
    console.log data
    lastMessageSeen = data.items[0].id
#setInterval pollBoard, 60 * 1000  # 60 seconds
