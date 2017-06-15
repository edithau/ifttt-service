IFTTT_CHANNEL_KEY = "hOBQF_3TQdVVTUtnncUko8px5k6JO8rwfAKmyA-ldIdOWpRrVtT_TVukgKrge2CT"

require "action_controller/railtie"
require "active_model/railtie"
require "nokogiri"
require "open-uri"

class StockInsiderPurchase < Rails::Application
  routes.append do
    #root to: "hello#world"

    get  "/ifttt/v1/status", to: "ifttt#status"
    post "/ifttt/v1/test/setup", to: "ifttt#setup"

    post "/ifttt/v1/triggers/insider_purchase", to: "ifttt#insider_purchase"
    post "/ifttt/v1/actions/notify_user", to: "ifttt#notify_user"
  end

  config.cache_store = :memory_store
  config.eager_load = false
  config.logger = Logger.new(STDOUT)
  config.secret_key_base = SecureRandom.hex(30)
end

class TickerList
  include ActiveModel::Model
  attr_accessor :created_at
  attr_accessor :tickers

  def self.all
    Rails.cache.fetch("TickerList") do
      [
          TickerList.new(created_at: Time.parse("Jan 1")),
          TickerList.new(created_at: Time.parse("Jan 2")),
          TickerList.new(created_at: Time.parse("Jan 3")),
      ]
    end
  end

  def self.create (tickers_str)
    TickerList.new.tap do |new_ticker_list|
      new_ticker_list.created_at = Time.now
      new_ticker_list.tickers = tickers_str
      Rails.cache.write("TickerList", all.push(new_ticker_list))
    end
  end

  def id
    created_at.to_i
  end

  def to_json
    {
        created_at: created_at.to_json,
        tickers: tickers,
        meta: { id: id, timestamp: created_at.to_i }
    }
  end

  def to_limited_json
    { id: id }
  end
end

class IftttController < ActionController::Base
  before_action :return_errors_unless_valid_channel_key
  before_action :return_errors_unless_valid_action_fields, only: :notify_user

  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  VALID_TICKERS_REGEX = /^[a-zA-Z,]+$/

  def status
    head :ok
  end

  def setup
    data = {
        "samples": {
            "actions": {
                "notify_user": {
                    "tickers": "aapl,goog,data",
                    "email": "me@example.com"
                }
            },
            "actionRecordSkipping": {
                "notify_user": {
                    "tickers": "",
                    "email": ""
                }
            }
        }
    }

    render plain: { data: data }.to_json
  end


  # trigger - return a new IFTTT event if there is a new insider purchase filing
  # no trigger fields on request; a comma separated ticker list on response
  def insider_purchase
    latest_tickers = self.class.latest_insider_purchase_tickers

    if !latest_tickers.empty? && (latest_tickers != TickerList.all.last.tickers)
        TickerList.create(latest_tickers)
    end

    data = TickerList.all.sort_by(&:created_at).reverse.map(&:to_json).first(params[:limit] || 50)
    render plain: { data: data }.to_json
  end


  # returns an array of tickers with today's insider purchase filing
  def self.latest_insider_purchase_tickers
    # this url is not the same as .embedded_link
    url = "http://openinsider.com/screener?s=&o=&pl=&ph=&ll=&lh=&fd=1&fdr=&td=0&tdr=&fdlyl=&fdlyh=&daysago=&xp=1&vl=&vh=&ocl=&och=&sic1=-1&sicl=100&sich=9999&grp=0&nfl=&nfh=&nil=&nih=&nol=&noh=&v2l=&v2h=&oc2l=&oc2h=&sortcol=0&cnt=100"
    html_content = Nokogiri::HTML(open(url))
    google_link = html_content.xpath('//div[@id="results"]/a/@href').map(&:value).find {|v| v.include? "www.google.com"}

    # no new purchase filing today if blank
    google_link.blank? ? [] : google_link.split(/=|,/)[1..-1]
  end



  # action - send email
  # a comma separated ticket list on request; a meaningless mandatory id on response.
  def notify_user
    cmd = self.class.compose_system_command(params['actionFields']['tickers'], params['actionFields']['email'])
    system(cmd + ' 2>&1 ')
    render plain: {data: [{id: Time.now}]}.to_json, status: 200
  rescue => e
     render plain: { errors: [ {status: "SKIP", message: "Cannot notify user.  Reason: #{e.message}" } ] }.to_json, status: 400
  end

  # return a unix system command string
  def self.compose_system_command (tickers, email)
    if !tickers.match(VALID_TICKERS_REGEX)
      raise "Invalid tickers format #{tickers}"
    end

    if !email.match(VALID_EMAIL_REGEX)
      raise "Invalid email format #{email}"
    end

    subject = "Insider purchase: #{tickers}"
    content = "Please check the link below for the latest insider purchase.'\n' #{embedded_link (tickers)}"

    "echo '#{content}' | mail -s '#{subject}' #{email}"
  end

  def self.embedded_link(tickers)
    "http://openinsider.com/screener?s=#{tickers}&o=&pl=&ph=&ll=&lh=&fd=365&fdr=&td=0&tdr=&fdlyl=&fdlyh=&daysago=&xp=1&vl=&vh=&ocl=&och=&sic1=-1&sicl=100&sich=9999&grp=0&nfl=&nfh=&nil=&nih=&nol=&noh=&v2l=&v2h=&oc2l=&oc2h=&sortcol=0&cnt=1000"
  end

  private

    def return_errors_unless_valid_channel_key
      unless request.headers["HTTP_IFTTT_CHANNEL_KEY"] == IFTTT_CHANNEL_KEY
        return render plain: { errors: [ { message: "401" } ] }.to_json, status: 401
      end
    end

    def return_errors_unless_valid_action_fields
      if params[:actionFields] && params[:actionFields][:invalid] == "true"
        return render plain: { errors: [ { status: "SKIP", message: "400" } ] }.to_json, status: 400
      end
    end
end

