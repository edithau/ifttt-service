require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "rails", "~> 5.0"
  gem 'nokogiri', '~> 1.6', '>= 1.6.8'
  gem 'byebug'
end

require './stock_insider_purchase.rb'



StockInsiderPurchase.initialize!
Rack::Server.start app: StockInsiderPurchase, Port: 3000
