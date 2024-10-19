require 'net/http'
require 'uri'
require 'json'
require 'nokogiri'
require 'proxylinker'
require 'thread'

class YahooFinanceScraper
  BASE_URL = "https://finance.yahoo.com/quote"
  MAX_RETRIES = 3
  MAX_REDIRECTS = 5
  MAX_THREADS = 10  # Juster dette tal efter behov

  def initialize(symbol_list)
    @symbol_list = symbol_list
    setup_proxy_manager
    @mutex = Mutex.new
  end

  def fetch_data
    threads = []
    queue = Queue.new
    @symbol_list.each { |symbol| queue << symbol }

    MAX_THREADS.times do
      threads << Thread.new do
        while !queue.empty?
          symbol = queue.pop(true) rescue nil
          break unless symbol

          %w[financials balance-sheet cash-flow].each do |page_type|
            fetch_data_for_symbol(symbol, page_type)
          end
        end
      end
    end

    threads.each(&:join)
  rescue Interrupt
    puts "\nAfbryder scraping proces..."
    exit(0)
  end

  private

  def fetch_data_for_symbol(symbol, page_type)
    retries = 0
    success = false

    while retries < MAX_RETRIES && !success
      @mutex.synchronize do
        puts "Henter data for: #{symbol} (#{page_type}) (Forsøg #{retries + 1}/#{MAX_RETRIES})"
      end

      begin
        proxy = get_proxy
        url = "#{BASE_URL}/#{symbol}/#{page_type}?p=#{symbol}"
        response = make_request(url, proxy)

        if response.is_a?(Net::HTTPSuccess)
          parse_page(response.body, symbol, page_type)
          @mutex.synchronize do
            puts "Færdig med at hente data for: #{symbol} (#{page_type})"
          end
          success = true
        else
          @mutex.synchronize do
            puts "Fejl ved hentning af data for: #{symbol} (#{page_type}) - Status: #{response.code}"
          end
          retries += 1
        end
      rescue => e
        @mutex.synchronize do
          puts "Fejl ved hentning af data for: #{symbol} (#{page_type}) - #{e.message}"
        end
        retries += 1
      end

      sleep(5) unless success # Vent lidt mellem forsøg
    end

    unless success
      @mutex.synchronize do
        puts "Kunne ikke hente data for: #{symbol} (#{page_type}) efter #{MAX_RETRIES} forsøg."
      end
    end
  end

  def setup_proxy_manager
    proxy_file_path = 'proxy_list.txt'
    @proxy_list = Proxylinker::ProxyList.new(proxy_file_path)
  end

  def get_proxy
    proxy = @proxy_list.get_random_proxy
    if proxy && proxy_works?(proxy)
      @mutex.synchronize do
        puts "Bruger proxy: #{proxy.addr}:#{proxy.port}"
      end
      proxy
    else
      @mutex.synchronize do
        puts "Ingen fungerende proxies tilgængelige. Prøver uden proxy."
      end
      nil
    end
  end

  def proxy_works?(proxy)
    uri = URI("https://finance.yahoo.com")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 10
    http.read_timeout = 10
    http.proxy_addr = proxy.addr
    http.proxy_port = proxy.port
    http.proxy_user = proxy.user if proxy.user
    http.proxy_pass = proxy.pass if proxy.pass

    begin
      response = http.get("/")
      return response.code.to_i == 200
    rescue
      return false
    end
  end

  def make_request(url, proxy = nil, redirect_count = 0)
    raise ArgumentError, 'For mange omdirigeringer' if redirect_count > MAX_REDIRECTS

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port, proxy&.addr, proxy&.port, proxy&.user, proxy&.pass)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 30
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = get_random_user_agent

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response
    when Net::HTTPRedirection
      location = response['location']
      @mutex.synchronize do
        puts "Omdirigerer til: #{location}"
      end
      make_request(location, proxy, redirect_count + 1)
    else
      response
    end
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

  def parse_page(html, symbol, page_type)
    doc = Nokogiri::HTML(html)
    section = doc.at_css('section.container.yf-1pgoo1f') # Opdater denne selector hvis nødvendigt

    if section
      headers = section.css('div.tableHeader div.column').map(&:text).map(&:strip)
      rows = section.css('div.tableBody div.row')

      rows.each do |row|
        data_type = row.at_css('div.rowTitle')&.text&.strip
        next unless data_type

        values = row.css('div.column').map(&:text).map(&:strip)

        headers.each_with_index do |header, index|
          year = header
          value = values[index]

          next if value.nil? || value.empty? || value == "--"

          @mutex.synchronize do
            puts "Symbol: #{symbol}, Side: #{page_type}, År: #{year}, Data type: #{data_type}, Værdi: #{value}"
          end
        end
      end
    else
      @mutex.synchronize do
        puts "Kunne ikke finde nogen tabel for #{symbol} (#{page_type})."
      end
    end
  end
end

# Liste over symboler
symbol_list = [
  "TSLA", "AAPL", "AMZN", "MSFT", "GOOGL", "FB", "NFLX", "NVDA", "BABA", "INTC",
  # ... (fortsæt med resten af dine symboler)
]

# Opretter instans af klassen og henter data
scraper = YahooFinanceScraper.new(symbol_list)
scraper.fetch_data
