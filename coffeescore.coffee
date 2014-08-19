https = require "https"
url = require "url"

urlbase = "https://api.hipchat.com/v2/"

settings =
    apiToken: ""
    roomId: 12345

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

getRecent = (not_before, handler) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.apiToken
    target += '&not_before=' + not_before if not_before
    jsonRequest 'GET', targetURL, null, handler

handleRecent = (data) ->
    for m in data.messages
        break if m.message.indexOf '@coffee' < 0

        if m.message.indexOf 'spare' > -1
            console.log 'spare requested'

        if m.message.indexOf 'me' > -1
            console.log 'spare requested'


checkIfExpired = () ->
    

pollBoard = ->
    getRecent handleRecent


postMessage = (msg, notify) ->
    target = "/v2/room/" + settings.roomId + "/notification?auth_token=" + settings.apiToken
    jsonRequest 'POST', target,
        message: msg
        notify: notify,
        (data) ->
            if data:
                console.log "Message send failed"
                console.log data

    


#setInterval pollBoard, 60 * 1000
#pollBoard()
postMessage 'Testing', false
