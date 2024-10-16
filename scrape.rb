require 'ferrum'
require 'nokogiri'
require 'faker'
require 'dotenv/load' # Loader miljøvariabler fra .env, hvis nødvendigt
require 'uri'
require 'net/http'
require 'json'

class YahooFinanceScraper
  BASE_URL = "https://finance.yahoo.com/quote"

  MAX_RETRIES = 1

  def initialize(symbol_list)
    @symbol_list = symbol_list
  end

  def fetch_data
    @symbol_list.each do |symbol|
      retries = 0
      success = false

      while retries < MAX_RETRIES && !success
        puts "Henter data for: #{symbol} (Forsøg #{retries + 1}/#{MAX_RETRIES}a)"

        begin
          setup_browser

          url = "#{BASE_URL}/#{symbol}/financials?p=#{symbol}"
          @browser.go_to(url)

          # Vent indtil siden er fuldt indlæst
          sleep(5)

          # Brug JavaScript til at klikke på knapperne, hvis de findes
          if @browser.at_css("#scroll-down-btn")
            @browser.execute("document.querySelector('#scroll-down-btn').click()")
            sleep(2)
          end
          if @browser.at_css("button.reject-all")
            @browser.execute("document.querySelector('button.reject-all').click()")
            sleep(2)
          end

          # Vent yderligere for at sikre, at siden er klar
          sleep(5)

          page = @browser.body
          parse_page(page, symbol)

          puts "Færdig med at hente data for: #{symbol}"
          success = true
        rescue Ferrum::TimeoutError
          puts "Timeout ved hentning af data for: #{symbol}"
          take_error_screenshot(symbol, retries + 1)
          retries += 1
        rescue Ferrum::BrowserError => e
          puts "Fejl ved hentning af data for: #{symbol} - #{e.message}"
          take_error_screenshot(symbol, retries + 1)
          retries += 1
        ensure
          @browser.quit if @browser
        end
      end

      unless success
        puts "Kunne ikke hente data for: #{symbol} efter #{MAX_RETRIES} forsøg."
      end
    end
  end

  private

  def setup_browser
    user_agent = get_random_user_agent
    puts "Bruger User-Agent: #{user_agent}"

    @browser = Ferrum::Browser.new(
      headless: false,
      user_agent: user_agent,
      window_size: [1200, 800]
      # Tilføj yderligere stealth-indstillinger her, hvis nødvendigt
    )
  end

  def get_random_user_agent
    user_agents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
      "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
    ]
    user_agents.sample
  end

  def parse_page(page, symbol)
    doc = Nokogiri::HTML(page)
    section = doc.at_css('section.container.yf-1pgoo1f') # Finder sektionen med den ønskede tabel

    if section
      headers = section.css('div.tableHeader div.column').map(&:text).map(&:strip) # Henter overskrifterne (årstal eller datafelter)
      rows = section.css('div.tableBody div.row') # Henter alle rækker i sektionen

      # Gå igennem alle rækker for at hente data
      rows.each do |row|
        data_type = row.at_css('div.rowTitle')&.text&.strip # Finder datatypen (f.eks. 'Total Revenue')
        next unless data_type # Skipper, hvis ingen datatype fundet

        values = row.css('div.column').map(&:text).map(&:strip) # Finder alle værdier i rækken (et år per kolonne)

        # Matcher værdier med de tilsvarende årstal (header)
        headers.each_with_index do |header, index|
          year = header
          value = values[index] # Finder den tilsvarende værdi

          next if value.nil? || value.empty? || value == "--"

          puts "Symbol: #{symbol}, År: #{year}, Data type: #{data_type}, Værdi: #{value}"
        end
      end
    else
      puts "Kunne ikke finde nogen tabel for #{symbol}."
    end
  end

  # Tag et screenshot ved fejl
  def take_error_screenshot(symbol, attempt)
    if @browser
      screenshot_name = "error_screenshot_#{symbol}_attempt_#{attempt}.png"
      @browser.screenshot.save(screenshot_name)
      puts "Error screenshot taget: #{screenshot_name}"
    end
  rescue => e
    puts "Fejl ved at tage screenshot: #{e.message}"
  end
end

# Liste over symboler
symbol_list = [
  "TSLA", "AAPL", "AMZN", "MSFT", "GOOGL", "FB", "NFLX", "NVDA", "BABA", "INTC", 
  "V", "MA", "PYPL", "ADBE", "ORCL", "CSCO", "CRM", "UBER", "LYFT", "SPOT",
  "BA", "NKE", "SBUX", "DIS", "KO", "PEP", "WMT", "TGT", "HD", "LOW", 
  "JPM", "GS", "BAC", "C", "WFC", "MS", "AMAT", "QCOM", "TXN", "MU",
  "AMD", "IBM", "HON", "GE", "MMM", "CAT", "UPS", "FDX", "XOM", "CVX"
]

# Opretter instans af klassen og henter data
scraper = YahooFinanceScraper.new(symbol_list)
scraper.fetch_data
