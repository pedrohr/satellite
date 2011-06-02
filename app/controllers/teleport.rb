require "yaml"
require "text"

require 'pp'
require 'store'

class Logger
  def self.success
    puts "\n\n"
    puts "(Teleport)"
    puts "  New object teleported!"
    puts ""
  end
  
  def self.fail
    puts "\n\n"
    puts "(Teleport)"
    puts "  Fail trying to save a new object teleported!"
    puts ""
  end
end

class Teleport
  # TODO: try/catch here
  @@config = YAML::load(File.open(Rails.root.to_s+'/config/teleport.yml')) 

  #hash: {satelite_attribute => teleport_attribute}
  @@mapping = {
    # TODO: load this from YAML config file
    # if user dont set the map on the yaml file, cosine distance will be used
    "occupation" => "occupation",
    "address" => "address",
    "name" => "name",
    "phone" => "phone",
    "__key" => "__key",
    "created_at" => "created_at",
    "updated_at" => "updated_at"}

  #calculates the cosine distance between two strings st1 and st2
  def self.cosine_distance(freq1, freq2)
    return 0 if freq1.empty? or freq2.empty?

    #optimizes future comparisons, tradeoff: dups for processing
    if freq1.size < freq2.size
      base = freq1.dup
      compare = freq2.dup
    else
      base = freq2.dup
      compare = freq1.dup
    end
    
    sum_base = 0
    sum_compare = 0
    dot_prod = 0

    #compute the dot product and the squared sum of the vector base
    base.each_pair do |key, value|
      sum_base += value * value
      image = compare[key]
      dot_prod += value * image
      sum_compare += image * image
      compare.delete(key)
    end

    compare.each_pair do |key,value|
      sum_compare += value * value
    end

    dot_prod/Math.sqrt(sum_base*sum_compare)
  end

  def self.get_model
    begin
      Kernel.const_get(@@config["model"])
    rescue NameError => e
      puts "======="
      puts "Invalid class name at 'model' in config file"
      puts "======="
    end
  end

  # TODO: handle errors by incorrect config file
  def self.get_entity
    @@config["entity"]
  end

  def self.gen_freq_vector(st)
    freq = Hash.new(0)
    st.to_s.downcase.gsub(/\s/,'').split(//).each do |char|
      freq[char] += 1
    end
    return freq
  end

  def self.load_frequency_vectors
    path = "#{Rails.root.to_s}/#{@@config["f_vec_directory"]}/#{get_model.to_s}_freq_vectors.gz"
    create_frequency_vectors unless File.exists?(path)
    freq_vectors = ObjectStore.load path
    return(freq_vectors)
  end

  def self.save_frequency_vectors(vectors)
    # TODO: verify consistency of config file
    path = "#{Rails.root.to_s}/#{@@config["f_vec_directory"]}"
    Dir.mkdir(path) unless File.directory?(path)    
    ObjectStore.store vectors, "#{path}/#{get_model.to_s}_freq_vectors.gz"
  end

  def self.create_frequency_vectors
    # fetching valid attributes
    attributes = get_model.new.attributes.dup
    ["__key","updated_at","created_at","id"].each do |k|
      attributes.delete(k)
    end

    db = get_model.find(:all)

    # sum all the attributes' values together into a same string and convert numbers into strings
    db.each do |tuple|
      attributes.each_pair do |k,v|
        attributes[k] = v.to_s + tuple[k].to_s.downcase
      end
    end

    # create a frequency vector for every attribute 
    attributes.each_pair do |k,v|
      freq = gen_freq_vector(v)
      attributes[k] = freq
    end

    save_frequency_vectors attributes
  end

  def self.mapper(val, info)
    default = @@mapping[val]
    return default unless (!info.has_key? default)

    # TODO: make this a static class varible
    freq_vectors = load_frequency_vectors
    cos_distance = {}

    # Cleaning info for mapping process
    infod = info.dup
    ["__key","updated_at","created_at","id"].each do |k|
      infod.delete(k)
    end

    # levenshtein distance to attributes' names
    infod.each_pair do |k,v|
      return k if Text::Levenshtein::distance(k,val) <= @@config["attr_names_threshold"]

      # Frequency vector of a value v of info
      freq1 = gen_freq_vector(v)
      cos_distance[k] = cosine_distance(freq_vectors[val],freq1)
    end

    biggest = cos_distance.max {|x,y| x.last <=> y.last}
    return nil unless @@config["cosine_threshold"] < biggest.last

    pp "-------------------------"
    pp "#{info[biggest.first]} -> #{val}, distance: #{biggest.last}"
    pp "-------------------------"

    # TODO: update freq_vectors in the file
    # TODO: optimize and 'refactorize'
    freq_vectors[val] = freq_vectors[val].merge(gen_freq_vector(info[biggest.first])){|k,a,b| a+b}

    save_frequency_vectors(freq_vectors)

    return biggest.first #TODO: insert default route (by config file) when none heuristics find a result
  end

  #Insert 'params' hash into some target object attributes
  #Ex.: All the attributes of the target object will be 
  #     filled with 'Person' under the mapping of 
  #     attributes
  def self.convert_params(params, target)
    entity = get_entity
    info = params[entity]
    hash = target.attributes

    hash.each do |key,value|
      target[key] = info[mapper(key, info)]
    end

    target["__key"] = params[entity]["__key"]
    
    return target
  end

  def self.convert_object(params, object)
    convert_params(params, object)
    return object
  end

  def self.convert_hash(params, object)
    convert_params(params, object)
    hash = object.attributes
    hash.delete_if {|k,v| v == nil}
    return hash
  end
end

#TODO: CandidatesController has to be passed as a parameter
# string.camelize.constantize
class CandidatesController < ApplicationController
  def teleport_save
    model = Teleport.get_model

    @candidate = model.find(:first, :conditions => {:__key => params["__key"]})
    
    unless @candidate == nil
      params["update"].each do |k,v|
        @candidate[k] = v
      end
      @candidate.save
    end

    render :nothing => true
  end
  
  def teleport_destroy
    model = Teleport.get_model
    entity = Teleport.get_entity

    key = params[entity]["__key"]
    @candidate = model.find(:first, :conditions => {:__key => key})
    @candidate.destroy unless @candidate == nil

    render :nothing => true
  end

  def teleport_create
    model = Teleport.get_model

    @candidate = model.new
    Teleport.convert_object(params, @candidate)

    if @candidate.save
      Logger.success
    else
      Logger.fail
    end

    render :nothing => true
  end
end
