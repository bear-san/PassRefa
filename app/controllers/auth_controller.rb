require 'devise'
require 'open-uri'
require 'json'
require 'uri'
require 'net/http'
require 'jwt'
require 'json/jwt'
class AuthController < ApplicationController
  
  
  def auth
    oidc_configuration = JSON.parse(open(ENV['OIDC_CONFIGURATION_URL']).read)
    
    # リダイレクト用URLの組み立て
    url = "#{oidc_configuration["authorization_endpoint"]}?client_id=#{ENV['OIDC_CLIENT_ID']}&redirect_uri=#{ENV['SERVER_HOST']}/auth/callback&scope=openid profile email&response_type=code"
    redirect_to(url)
  end
  
  def callback
    oidc_configuration = JSON.parse(open(ENV['OIDC_CONFIGURATION_URL']).read)
    
    # id_tokenの取得
    token_url = URI.parse(oidc_configuration["token_endpoint"])
    
    req = Net::HTTP::Post.new(token_url.path)
    req.set_form_data({
                        "code" => params["code"],
                        "client_id" => ENV['OIDC_CLIENT_ID'],
                        "client_secret" => ENV['OIDC_CLIENT_SECRET'],
                        "grant_type" => "authorization_code",
                        "scope" => "openid profile email",
                        "redirect_uri" => "#{ENV['SERVER_HOST']}/auth/callback"
                      })
    
    response = Net::HTTP.start(token_url.host, token_url.port, :use_ssl => token_url.scheme == "https") do |http|
      http.request(req)
    end
    
    response_dict = JSON.parse(response.body)
    
    # id_tokenの検証
    unverified_id_token = JWT.decode(response_dict['id_token'], nil, false)
    
    jwks = JSON.parse(open(oidc_configuration["jwks_uri"]).read)
    jwk = jwks["keys"].filter{ |k| k["kid"] = unverified_id_token[1]["kid"] }[0]
    
    id_token = JWT.decode(response_dict['id_token'], JSON::JWK.new(jwk).to_key, true, :algorithm => jwk["alg"])
    
    userinfo = id_token[0]
    
    # userinfoの検証
    time = DateTime.now
    if userinfo["iss"] != oidc_configuration["issuer"] or userinfo["aud"] != ENV['OIDC_CLIENT_ID'] or userinfo["exp"] < time.to_i or time.to_i < userinfo["iat"] then
      render plain: "invalid credential data", status: 400
      return
    end
    
    
  end
end
