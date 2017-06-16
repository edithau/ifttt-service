require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/unit'
require './stock_insider_purchase.rb'
require 'byebug'

require 'uri'

class MyMiniTest < MiniTest::Unit::TestCase
  def test_valid_link
    # test the link included in the email is valid

    tickers = 'aapl'
    my_link = IftttController.embedded_link(tickers)
    assert_includes my_link, tickers, "#{tickers} should be included in the url"
    assert my_link.match(/https?:\/\/[\S]+$/).to_s == my_link, "should be a valid url"
  end

  def test_invalid_link
    tickers = 'aapl goog'
    my_link = IftttController.embedded_link(tickers)
    assert my_link.match(/https?:\/\/[\S]+$/) == nil, "should not contain space chars in a url"
  end

  def test_compose_system_command
    raw_tickers = '[\"AAPL\", \"GOOG\", \"DATA\"]'
    tickers = 'AAPL,GOOG,DATA'

    email = 'abc@example.com'

    command_str = IftttController.compose_system_command(raw_tickers, email)
    assert_includes command_str, tickers, "system command should include tickers #{tickers}"
    assert_includes command_str, email, "system command should include email #{email}"
  end
end