https = require 'https'
json = require 'json'
url = require 'url'

settings =
    apiToken: ''
    roomId: 12345

addQueryParams = (base, params) ->
    urlBase = url.parse base, true
    # Merge in
    urlBase.query[k] = params[k] for k of params
    return url.format urlBase


jsonRequest = (url, handler) ->
    https.get targetURL, handler (res) ->
        data = ''
        res.on 'data', (chunk) ->
            data += chunk
        res.on 'end', (chunk) ->
            obj = json.parse data
            handler data

getRecent = (handler) ->
    targetURL = addQueryParams 'https://api.hipchat.com/v1/rooms/history',
        auth_token: settings.apiToken
        room_id: settings.roomId
        date: 'recent'
        format: 'json'
    console.log targetURL

    jsonRequest targetURL, handler


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
    checkIfExpired()
    


setInterval pollBoard, 60 * 1000
pollBoard()
