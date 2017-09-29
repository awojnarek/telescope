#!/usr/bin/env ruby
require 'optparse'
require 'pp'
require 'csv'
require 'json'
require 'net/http'

#############
# Variables #
#############


################
# Optionparser #
################
options = {}

# Set the possible options
optparse = OptionParser.new do |opts|

  opts.on('-i ITEM_ID', '--item-id ITEM_ID', 'itemid') do |o|
    options[:itemid] = o
  end

  opts.on('-s site', '--site SITE', 'site') do |o|
    options[:site] = o
  end
  
  opts.on('-T TOKEN', '--token TOKEN', 'token') do |o|
    options[:token] = o
  end

  opts.on('-t TIME', '--time TIME', 'time') do |o|
    options[:time] = o
  end

  opts.on('-o OFFER', '--offer-file FILE', 'offer') do |o|
    options[:offer] = o
  end

  opts.on('-C', '--cache-offer-file', 'cache') do |o|
    options[:cache] = true
  end

  opts.on('-r REGION', '--region REGION', 'region') do |o|
    options[:region] = o
  end

  opts.on('-?', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

begin
  # Parse the options we've set above
  optparse.parse!

rescue OptionParser::InvalidOption => e
  puts "#{e}, try running ./telescope.rb -h for help"
  exit
end


#############
# Functions #
#############

def parse_cpu_csv(csv)
  begin

    # Let's make sure this is the right chart
    headers = CSV.parse(csv).first

    return false if ! headers.grep(/CPU Consumed/).count == 1

    # Store our data
    array = []
    data  = Hash.new

    CSV.parse(csv, headers: true) do |row|
      cpus = row.fields.last
      next if cpus == nil
      cpus = cpus.to_f
      array.push(cpus)
    end

    # Find our average
    average = array.inject{ |sum, e| sum + e}.to_f / array.size
    average = average.round(2)

    # Find our peak
    peak = array.max


    data["average"] = average
    data["peak"]    = peak.round(2)
 
    return data

  rescue => e
    printf "Error in parse_cpu_file => #{e}\n"
    exit 1
  end
end

def parse_memory_csv(csv)
  begin

    # Let's make sure this is the right chart
    headers = CSV.parse(csv).first
    return false if ! headers.grep(/Buffers/).count == 1

    # Store our data
    array_without_cache = []
    array_with_cache    = []
    data  = Hash.new { |hash, key| hash[key] = {} }

    CSV.parse(csv, headers: true) do |row|
      fields = row.fields.reject{ |e| e =~ /-/ or e =~ /:/}
      process = fields[1].to_f
      cache   = fields[2].to_f + fields[3].to_f
      total   = process + cache

      array_without_cache.push(process)
      array_with_cache.push(total)
    end

    average_with_cache    = array_with_cache.inject{    |sum, e| sum + e }.to_f / array_with_cache.size
    average_without_cache = array_without_cache.inject{ |sum, e| sum + e }.to_f / array_without_cache.size
    peak_with_cache       = array_with_cache.max
    peak_without_cache    = array_without_cache.max

    data["cache"]["average"]    = average_with_cache.round(2)
    data["cache"]["peak"]       = peak_with_cache.round(2)
    data["no cache"]["average"] = average_without_cache.round(2)
    data["no cache"]["peak"]    = peak_without_cache.round(2)

    return data

  rescue => e
    printf "Error in parse_memory_file => #{e}\n"
    exit 1
  end
end

def cache_offer()

  %x[curl -s https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/index.json > cache.json]

  if $?.exitstatus == 0
    return "cache.json"
  else
    return false
  end

  # TODO Need to rewrite this with native file IO
  #uri = URI('https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/index.json')
  #Net::HTTP.start(uri.host, uri.port) do |http|
  #  request = Net::HTTP.get uri
  #  http.request request do |response|
  #    open 'large_file', 'w' do |io|
  #      response.read_body do |chunk|
  #        io.write chunk
  #      end
  #    end
  #  end
  #end

end

def parse_text_to_data_hash(file)

  if file == nil
    printf "you must cache a json file, non-cached files not supported yet\n"
    exit 1
  end

  json_file = File.read(file)
  data_hash = JSON.parse(json_file)

  return data_hash
end

def simplify_data_hash(json)

  #data  = Hash.new {|h,k| h[k] = Hash.new(&h.default_proc) }
  data  = Hash.new { |hash, key| hash[key] = [] }

  json.each do |k,v|

    next unless k == "products"
    products      = v

    products.each do |k,v|
      hash = v
   
      # Let's rule out some things so we don't have to eval
      next unless hash["productFamily"]              == "Compute Instance"
      next unless hash["attributes"].has_key?("locationType")
      next unless hash["attributes"]["locationType"] == "AWS Region"

      attr = hash["attributes"]

      instance_type = attr["instanceType"]
      family        = attr["instanceFamily"]
      location      = attr["location"]
      vcpus         = attr["vcpu"]
      memory        = attr["memory"]
      storage       = attr["storage"]
      clock         = attr["clockSpeed"]
      network       = attr["networkPerformance"]
      os            = attr["operatingSystem"]
      sku           = attr["sku"]

      subdata = { "family"   => family,
                  "vcpus"    => vcpus,
                  "memory"   => memory,
                  "storage"  => storage,
                  "clock"    => clock,
                  "network"  => network,
                  "location" => location,
                  "os"       => os, 
                  "sku"      => sku }

      data[instance_type].push(subdata)
    end
  end

  return data
end

def build_url(site,item_id,time,chart_id,token)
  url = "https://my.galileosuite.com/#{site}/export.csv_raw?"
  url = "#{url}item_id=#{item_id}&"
  url = "#{url}range_type=#{time}&"
  url = "#{url}chart_id=#{chart_id}&"
  url = "#{url}t=#{token}"

  return url
end

def is_asset_linux?(site,item_id,token)
  # If we pull data from chart_id 1 and 83

  url1 = build_url(site,item_id,"last_240","1",token)
  url2 = build_url(site,item_id,"last_240","83",token)
  curl1 = %x[curl -s --data "" "#{url1}" 2>&1]
  curl2 = %x[curl -s --data "" "#{url2}" 2>&1]

  if curl1 =~ /error/
    return false
  end

  if curl2 =~ /error/
    return false
  end
  
  return true

end

def pull_linux_data(site,item_id,time,token)

  data = Hash.new

  # Let's pull CPU CSV
  #
  cpu_url = build_url(site,item_id,time,"83",token)
  cpu_csv = %x[curl -s --data "" "#{cpu_url}" 2>&1]
  parsed_cpu = parse_cpu_csv(cpu_csv)

  # Let's pull Memory CSV
  #
  memory_url = build_url(site,item_id,time,"82",token)
  memory_csv = %x[curl -s --data "" "#{memory_url}" 2>&1]
  parsed_mem = parse_memory_csv(memory_csv)
 
  data["cpu"]    = parsed_cpu
  data["memory"] = parsed_mem

  return data

end

def pull_machine_data(site,item_id,token,*time)

  # Find our time
  #
  time = "last_1440" if time.join("") == "" or time.join("") == nil

  # Let's determine what kind of asset this is
  #
  asset_type = nil

  until asset_type != nil
    asset_type = "Linux" if is_asset_linux?(site,item_id,token) 
  end

  data = Hash.new { |hash, key| hash[key] = [] }
  case asset_type
  when "Linux"
    data = pull_linux_data(site,item_id,time,token)
  end

  return data

end
########
# Main #
########

####################
# AWS DATA PARSING #
#------------------#
# Cache our offering file from AWS
=begin
if options[:cache] == true
  printf "Caching AWS JSON offering\n"
  rc = cache_offer

  if rc == false
    printf "unable to cache offering file\n"
    exit
  else
    printf "Wrote: #{rc}\n"
    exit
  end
end

# Use our cached copy if wanted
#
offer = options[:offer] if options[:offer]

# Let's parse the JSON
#
json = parse_text_to_data_hash(offer)

# Let's put it into a format we can understand
#
data = simplify_data_hash(json)
=end


########################
# Galileo DATA PARSING #
#----------------------#
if options[:itemid] == nil
  printf "you must specify an item_id\n"
  exit 1
end

if options[:site] == nil
  printf "you must specify an site\n"
  exit 1
end

if options[:token] == nil
  printf "you must specify an token\n"
  exit 1
end

item_id = options[:itemid] if options[:itemid]
time    = options[:time]   if options[:time]
site    = options[:site]   if options[:site]
token   = options[:token]  if options[:token]

machine_data = pull_machine_data(site,item_id,token,time)
pp machine_data


exit
# Find our CPU to Memory Ratio
#
cpu_memory_ratio = cpu["average"].to_f / (memory["cache"]["average"] / 1024).to_f


printf "CPU average/peak: #{cpu["average"]}, #{cpu["peak"]}\n"
printf "Memory average/peak: #{memory["average"]}, #{memory["peak"]}\n"

pp memory
