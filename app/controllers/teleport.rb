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

class Teleporter
  # TODO: try/catch here
  @@config = YAML::load(File.open(Rails.root.to_s+'/config/teleport.yml')) 

  #hash: {satelite_attribute => teleport_attribute}
  @@mapping = {
    # TODO: load this from YAML config file
    # if user dont set the map on the yaml file, cosine distance will be used
    # central => satellite
    "occupation" => "occupation",
    "address" => "address",
    "name" => "name",
    "phone" => "phone"}

  @@default_hard_links = {
    "__key" => "__key", #important!
    "created_at" => "created_at",
    "updated_at" => "updated_at"}

  @@black_list = ["id"]

  # this should exists in a middleware like Warden, but I need the remote IP address anyway, so I'd better check for any allowance policy
  def self.allow_request(ip)
    @@config["satellites"].include? ip
  end

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

  def self.mapper(infod)
    freq_vectors = load_frequency_vectors

    info = infod.dup

    mapping = {}
    # TODO: load hard links to avoid unecessary comparisons

    #removing defaults and edit-distance matchings
    freq_vectors.each_pair do |k,v|
      default = @@mapping[k]
      if info.has_key? default
        mapping[k] = default
        freq_vectors.delete(k)
        info.delete(default)
      else
        info.each_pair do |ik, iv|
          if Text::Levenshtein::distance(k,ik) <= @@config["attr_names_threshold"]
            mapping[k] = ik
            freq_vectors.delete(k)
            info.delete(ik)
          end
        end
      end
      #write hard link
    end

    #building full-connected weighted graph
    comparisons = {}
    freq_vectors.each_pair do |k,v|
      comparisons[k] = {}
      mapping[k] = {}
      info.each_pair do |ik, iv|
        comparisons[k][ik] = cosine_distance(gen_freq_vector(iv), v) unless iv.empty?
      end
    end

    until comparisons.empty? do
      #taking the highest weight edge
      greatest = ["","",0]
      comparisons.each do |attr|
        # no more satellite attributes to use
        if attr.last.empty?
          greatest[0] = attr.first
          greatest[1] = nil
          break
        end

        big = attr.last.max {|x,y| x.last <=> y.last}
        if greatest.last <= big.last
          greatest[0] = attr.first #ugly for Ruby, I know!
          greatest[1] = big.first
          greatest[2] = big.last
        end
      end

      #deleting all incident edges to the 2-size cluster
      comparisons.delete(greatest.first)
      comparisons.each do |attr|
        attr.last.delete(greatest[1])
      end

      mapping[greatest.first] = greatest[1]

      if greatest.last > @@config["cosine_threshold"]
        #save hard link
      end
    end

    #TODO: update freq_vectors

    return mapping
  end

  def self.convert_params(params, target)
    info = params[get_entity]

    @@black_list.each do |black|
      info.delete(black)
    end

    @@default_hard_links.each do |k,v|
      target[k] = info[v]
      info.delete(v)
    end

    mapping = mapper(info)

    target.attributes.each do |key,value|
      target[key] = info[mapping[key]] if target[key].nil?
    end

    # Updating freq_vectors
    freq_vectors = load_frequency_vectors
    mapping.each_pair do |k,v|
      freq_vectors[k] = freq_vectors[k].merge(gen_freq_vector(info[v])){|key,a,b| a+b} unless info[v].nil?
    end
    save_frequency_vectors(freq_vectors)    

    pp freq_vectors

    # TODO: this must go to a (decent) Logger
    pp mapping
    
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


module Teleport
  def teleport_save
    render :nothing => true unless Teleporter.allow_request(request.env["REMOTE_ADDR"])

    model = Teleporter.get_model

    @tuple = model.find(:first, :conditions => {:__key => params["__key"]})
    
    unless @tuple == nil
      ############### TODO: need a convert_params here !
      params["update"].each do |k,v|
        @tuple[k] = v
      end
      @tuple.save
    end

    render :nothing => true
  end
  
  def teleport_destroy
    render :nothing => true unless Teleporter.allow_request(request.env["REMOTE_ADDR"])

    model = Teleporter.get_model
    entity = Teleporter.get_entity

    key = params[entity]["__key"]
    @tuple = model.find(:first, :conditions => {:__key => key})
    @tuple.destroy unless @tuple == nil

    render :nothing => true
  end

  def teleport_create
    render :nothing => true unless Teleporter.allow_request(request.env["REMOTE_ADDR"])

    model = Teleporter.get_model

    @tuple = model.new
    Teleporter.convert_object(params, @tuple)

    if @tuple.save
      Logger.success
    else
      Logger.fail
    end

    render :nothing => true
  end
end
