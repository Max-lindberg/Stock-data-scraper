# scraper.rb
require 'ferrum'
require 'nokogiri'
require 'faker'
require 'dotenv/load' # Loader miljøvariabler fra .env, hvis nødvendigt
require 'uri'
require 'net/http'
require 'json'

class SeekingAlphaScraper
  BASE_URL = "https://seekingalpha.com/symbol"

  MAX_RETRIES = 3

  def initialize(symbol_list)
    @symbol_list = symbol_list
  end

  def fetch_data
    @symbol_list.each do |symbol|
      retries = 0
      success = false

      while retries < MAX_RETRIES && !success
        puts "Henter data for: #{symbol} (Forsøg #{retries + 1}/#{MAX_RETRIES})"

        begin
          setup_browser

          check_robots_txt

          url = "#{BASE_URL}/#{symbol}/income-statement"
          @browser.go_to(url)

          # Tilfældig ventetid mellem 5 og 15 sekunder
          sleep(rand(5..15))

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
    table = doc.at_css('table[data-test-id="table"]') # Finder tabellen baseret på dens 'data-test-id'

    if table
      headers = table.css('thead th').map(&:text).map(&:strip) # Henter overskrifterne (årstal eller datafelter)
      rows = table.css('tbody tr')    # Henter alle rækker i tabellen

      # Gå igennem alle rækker for at hente data
      rows.each do |row|
        data_type = row.at_css('th')&.text&.strip # Finder datatypen (f.eks. 'Revenues')
        next unless data_type # Skipper, hvis ingen datatype fundet

        values = row.css('td').map(&:text).map(&:strip) # Finder alle værdier i rækken (et år per kolonne)

        # Matcher værdier med de tilsvarende årstal (header)
        headers.each_with_index do |header, index|
          year = header
          value = values[index] # Finder den tilsvarende værdi

          # Filtrer værdier, der er tomme eller har "view ratings"
          next if value.nil? || value.empty? || value.downcase.include?("view ratings")

          puts "Symbol: #{symbol}, År: #{year}, Data type: #{data_type}, Værdi: #{value}"
        end
      end
    else
      puts "Kunne ikke finde nogen tabel for #{symbol}."
    end
  end

  def check_robots_txt
    robots_url = "https://seekingalpha.com/robots.txt"
    uri = URI(robots_url)
    response = Net::HTTP.get(uri)

    # Simpel kontrol: Tjek om "Disallow: /symbol" findes
    disallowed_paths = response.scan(/Disallow: (.+)/).flatten
    symbol_path = "/symbol"

    if disallowed_paths.any? { |path| symbol_path.start_with?(path) }
      raise "Scraping af #{symbol_path} er ikke tilladt ifølge robots.txt"
    end
  rescue => e
    puts "Fejl ved tjek af robots.txt: #{e.message}"
    # Fortsæt eller stop afhængigt af dine behov
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
scraper = SeekingAlphaScraper.new(symbol_list)
scraper.fetch_data
