#!ruby

require 'sinatra'
require "sinatra/reloader"
require 'multi_json'
require 'ringcentral_sdk'

require 'pry'

set :port, ENV['MY_APP_PORT']
register Sinatra::Reloader

# Enter config in .env file
client = RingCentralSdk::REST::Client.new
config = RingCentralSdk::REST::Config.new.load_dotenv
client.set_app_config config.app

get '/' do
  render_index(client)
end

get '/callback' do
  code = params.key?('code') ? params['code'] : ''
  client.authorize_code(code) if code
  ''
end

get '/subscribe' do
  response = client.http.post do |req|
    req.url 'subscription?aggregated=True'
    req.headers['Content-Type'] = 'application/json'
    req.body = {
      eventFilters: [
        '/restapi/v1.0/account/~/extension/~/message-store'
      ],
      deliveryMode: {
        transportType: 'WebHook',
        address: 'https://textus.ngrok.io/sms'
      }
    }
  end

  puts "#{"* " * 10} SUBSCRIBE: #{response.status}"

  render_index(client)
  redirect back
end

get '/renew' do
  response = client.http.get do |req|
    req.url 'subscription'
    req.headers['Content-Type'] = 'application/json'
  end

  record = response.body.to_hash['records'].first

  response = client.http.put do |req|
    req.url "subscription/#{record["id"]}"
    req.headers['Content-Type'] = 'application/json'
    req.body = {}
  end

  render_index(client)
  redirect back
end

get '/send' do
  client.messages.sms.create(
    from: '+12679230829',
    to: '+12679230829',
    text: 'Automated test'
  )

  render_index(client)
  redirect back
end

post '/sms' do
  if env['HTTP_VALIDATION_TOKEN']
    response.headers['Validation-Token'] = env['HTTP_VALIDATION_TOKEN']
  end

  if request.body.kind_of?(StringIO)
    body_string = request.body.read

    if !body_string.empty?
      body_hash = JSON.parse(body_string)

      if !body_hash.empty?
        puts "#{"* " * 10} RECEIVE: #{body_hash}"

        event = RingCentralSdk::REST::Event.new body_hash
        retriever = RingCentralSdk::REST::MessagesRetriever.new client
        messages = retriever.retrieve_for_event event, direction: 'Inbound'

        messages.each do |message|
          puts "#{"* " * 10} MESSAGE: #{message}}"
        end
      end
    end
  end

  status 200
end

get '/cancel-all' do
  response = client.http.get do |req|
    req.url 'subscription'
    req.headers['Content-Type'] = 'application/json'
  end

  response.body.to_hash['records'].each do |record|
    client.http.delete do |req|
      req.url "subscription/#{record["id"]}"
      req.headers['Content-Type'] = 'application/json'
    end
  end

  render_index(client)
  redirect back
end

def render_index(client)
  token_json = client.token.nil? \
    ? '' : MultiJson.encode(client.token.to_hash, pretty: true)

  subscriptions = ''
  if client.http
    response = client.http.get do |req|
      req.url 'subscription'
      req.headers['Content-Type'] = 'application/json'
    end

    subscriptions = response.body.empty? ? '' :
      MultiJson.encode(response.body.to_hash, pretty: true)
  end

  phone_numbers = ''
  if client.http
    response = client.http.get do |req|
      req.url 'account/~/phone-number'
      req.headers['Content-Type'] = 'application/json'
    end

    phone_numbers = response.body.empty? ? '' :
      MultiJson.encode(response.body.to_hash, pretty: true)
  end

  erb :index, locals: {
    authorize_uri: client.authorize_url(),
    redirect_uri: client.app_config.redirect_url,
    token_json: token_json,
    phone_numbers: phone_numbers,
    subscriptions: subscriptions }
end
