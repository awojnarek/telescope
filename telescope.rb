#!/usr/bin/env ruby
require 'optparse'
require 'pp'
require 'csv'
require 'json'
require 'net/http'
require 'yaml'

#############
# Variables #
#############
Current_Dir       = File.expand_path File.dirname(__FILE__)
CPU_Memory_Ratios = "#{Current_Dir}/cpu_memory_ratios.yml"

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

def nested_hash_value(obj,key)
  if obj.respond_to?(:key?) && obj.key?(key)
    obj[key]
  elsif obj.respond_to?(:each)
    r = nil
    obj.find{ |*a| r=nested_hash_value(a.last,key) }
    r
  end
end

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
      sku           = hash["sku"]

      # Now let's find out price
      reserved_sku  = json["terms"]["Reserved"][sku]
      on_demand_sku = json["terms"]["OnDemand"][sku]
      
      reserved_unit  = nested_hash_value(reserved_sku,"unit")
      reserved_price = nested_hash_value(reserved_sku,"USD")
     
      on_demand_unit  = nested_hash_value(on_demand_sku,"unit")
      on_demand_price = nested_hash_value(on_demand_sku,"USD")
      
      subdata = { "family"          => family,
                  "vcpus"           => vcpus,
                  "memory"          => memory,
                  "storage"         => storage,
                  "clock"           => clock,
                  "network"         => network,
                  "location"        => location,
                  "os"              => os, 
                  "reserved_unit"   => reserved_unit,
                  "on_demand_unit"  => on_demand_unit,
                  "reserved_price"  => reserved_price,
                  "on_demand_price" => on_demand_price }

      data[instance_type].push(subdata)
      data[instance_type].uniq!
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
aws_data = simplify_data_hash(json)

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
region  = options[:region] if options[:region]
region  = "US East (Ohio)" if region == nil

machine_data = pull_machine_data(site,item_id,token,time)

cpuavg    = machine_data["cpu"]["average"]
cpupeak   = machine_data["cpu"]["peak"]
memavg    = machine_data["memory"]["cache"]["average"] / 1024
mempeak   = machine_data["memory"]["cache"]["peak"] / 1024
memavgnc  = machine_data["memory"]["no cache"]["average"] / 1024
mempeaknc = machine_data["memory"]["no cache"]["peak"] / 1024

# Find our CPU to Memory Ratio
#
cpu_memory_ratio   = machine_data["cpu"]["average"].to_f / (machine_data["memory"]["cache"]["average"] / 1024).to_f
cpu_ncmemory_ratio = machine_data["cpu"]["average"].to_f / (machine_data["memory"]["no cache"]["average"] / 1024).to_f

printf "\n##################\n"
printf "# Machine Summary#\n"
printf "#----------------#\n"
printf "%-10s %-10s %-10s %-12s %-12s %-22s %-22s\n", "item_id", "CPU Avg", "CPU Peak", "Memory Avg", "Memory Peak", "Memory No Cache Avg", "Memory No Cache Peak"
printf "%-10s %-10s %-10s %-12s %-12s %-22s %-22s\n", item_id, cpuavg, cpupeak, memavg.round(2), mempeak.round(2), memavgnc.round(2), mempeaknc.round(2)


=begin
printf "\n########### CPU/Memory Ratio #############\n"
printf "%-10s %-25s %-25s\n", "item_id", "CPU/Memory Ratio", "CPU/Memory No Cache Ratio"
printf "%-10s %-25s %-25s\n", item_id, cpu_memory_ratio.round(2), cpu_ncmemory_ratio.round(2)
=end

=begin
###################################
# Load Static CPU / Memory Ratios #
#---------------------------------#
if ! File.exist?(CPU_Memory_Ratios)
  printf "#{CPU_Memory_Ratios} file doesn't exist\n"
  exit
end

ratios = YAML.load_file(CPU_Memory_Ratios)
=end

printf "\n#############################\n"
printf "# Predictive Instance Guess #\n"
printf "#---------------------------#\n"
printf "%-15s %-8s %-10s %-20s %-20s %-10s %-20s %-15s %-25s %-25s\n", "Type", "vCPUs", "Memory", "Family", "Storage", "Clock", "Network", "Region", "Reserved Price (mo)", "On Demand Price (mo)"
aws_data.each do |k,v|
  v.each do |e|
    next unless e["location"] == region 
    next unless e["os"] == "Linux"

    
    instance_memory = e["memory"].split(" ")[0].to_f

    reserved_price = nil
    unless e["reserved_unit"] == nil or e["reserved_unit"] == "Quantity"
      if e["reserved_unit"] == "Hrs"
        reserved_price = (e["reserved_price"].to_f * 720).round(2)
      end

      if e["reserved_unit"] == "Quantity"
        reserved_price = e["reserved_price"]
      end
    end

    on_demand_price = nil
    unless e["on_demand_unit"] == nil or e["on_demand_unit"] == "Quantity"
      if e["on_demand_unit"] == "Hrs"
        on_demand_price = (e["on_demand_price"].to_f * 720).round(2)
      end

      if e["on_demand_unit"] == "Quantity"
        on_demand_price = e["on_demand_price"]
      end
    end
    
    next if on_demand_price == nil and reserved_price == nil
    next if on_demand_price == 0.0 and reserved_price == 0.0
    next if on_demand_price == ""  and reserved_price == ""
    next if on_demand_price == ""  and reserved_price == 0.0
    next if on_demand_price == nil and reserved_price == 0.0

    if e["vcpus"].to_f > cpuavg.to_f and instance_memory > memavgnc
      printf "%-15s %-8s %-10s %-20s %-20s %-10s %-20s %-15s %-25s %-25s\n", k, e["vcpus"], e["memory"], e["family"], e["storage"], e["clock"], e["network"], e["location"], "$#{reserved_price}", "$#{on_demand_price}" 
    end
  end
end
