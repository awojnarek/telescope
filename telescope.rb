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

  opts.on('-c CPU', '--CPU-CSV FILE', 'cpu') do |o|
    options[:cpu] = o
  end

  opts.on('-m MEMORY', '--Memory-CSV FILE', 'memory') do |o|
    options[:memory] = o
  end

  opts.on('-d DISK', '--Disk-CSV FILE', 'disk') do |o|
    options[:disk] = o
  end

  opts.on('-n NETWORK', '--Network-CSV FILE', 'network') do |o|
    options[:disk] = o
  end

  opts.on('-s', '--summary-only', 'summary') do |o|
    options[:summary] = true
  end

  opts.on('-p', '--project-cost', 'project') do |o|
    options[:project] = true
  end

  opts.on('-o OFFER', '--offer-file FILE', 'offer') do |o|
    options[:offer] = o
  end

  opts.on('-C', '--cache-offer-file', 'cache') do |o|
    options[:cache] = true
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

def parse_cpu_file(file)
  begin

    # Let's make sure this is the right chart
    headers = CSV.read(file).first
    return false if ! headers.grep(/CPU Consumed/).count == 1

    # Store our data
    array = []
    data  = Hash.new

    CSV.foreach(file, headers: true) do |row|
      cpus = row.fields.last
      next if cpus == nil
      cpus = cpus.to_f
      array.push(cpus)
    end

    # Find our average
    average = array.inject{ |sum, e| sum + e}.to_f / array.size
    average = average.round

    # Find our peak
    peak = array.max


    data["average"] = average
    data["peak"]    = peak.round
 
    return data

  rescue => e
    printf "Error in parse_cpu_file => #{e}\n"
    exit 1
  end
end

def parse_memory_file(file)
  begin

    # Let's make sure this is the right chart
    headers = CSV.read(file).first
    return false if ! headers.grep(/Buffers/).count == 1

    # Store our data
    array_without_cache = []
    array_with_cache    = []
    data  = Hash.new { |hash, key| hash[key] = {} }

    CSV.foreach(file, headers: true) do |row|
      fields = row.fields.reject{ |e| e =~ /-/ or e =~ /:/}
      process = fields[0].to_f
      cache   = fields[1].to_f + fields[2].to_f
      total   = process + cache

      array_without_cache.push(process)
      array_with_cache.push(total)
    end

    average_with_cache    = array_with_cache.inject{    |sum, e| sum + e }.to_f / array_with_cache.size
    average_without_cache = array_without_cache.inject{ |sum, e| sum + e }.to_f / array_without_cache.size
    peak_with_cache       = array_with_cache.max
    peak_without_cache    = array_without_cache.max

    data["cache"]["average"]    = average_with_cache.round
    data["cache"]["peak"]       = peak_with_cache.round
    data["no cache"]["average"] = average_without_cache.round
    data["no cache"]["peak"]    = peak_without_cache.round

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

########
# Main #
########

if options[:cache] == true
  printf "Caching AWS JSON offering\n"
  rc = cache_offer

  printf "Wrote: #{rc}\n"
  exit
end

# Let's grab our CPU information
#
cpu = nil
if options[:cpu] != nil and File.exists?(options[:cpu])
  cpu = parse_cpu_file(options[:cpu]) 
end

# Let's grab our Memory information
# 
memory = nil
if options[:memory] != nil and File.exists?(options[:memory])
  memory = parse_memory_file(options[:memory]) 
end

# Now that we have data, let's try and figure out an instance type based on CPU and memory
#
cpu_memory_ratio = cpu["average"].to_f / (memory["cache"]["average"] / 1024).to_f


