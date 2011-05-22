require "yaml"
require "text"

require 'pp'

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

class Teleport_receiver
  @@config = YAML::load(File.open(RAILS_ROOT+'/config/teleport.yml')) 

  #hash: {satelite_attribute => teleport_attribute}
  #TODO: this mapping should be created automatically
  @@mapping = {
    "occupation" => "occupation",
    "address" => "address",
    "name" => "name",
    "phone" => "phone"}

  #Satellite param
  @@key = "name"

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

  #TODO: handle nil cases
  def self.mapper(val, info)
    default = @@mapping[val]
    return default unless (! info.has_key? default)

    # levenshtein distance to attributes' names
    info.each_pair do |k,v|
      return k if Text::Levenshtein::distance(k,val) <= @@config["attr_names_threshold"]
    end

    return nil #TODO: insert default route (by config file) when none heuristics find a result
  end

  #Insert 'params' hash into some target object attributes
  #Ex.: All the attributes of the target object will be 
  #     filled with 'Person' under the mapping of 
  #     attributes
  def self.convert_params(params, target)
    entity = @@config["entity"]
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

class CandidatesController < ApplicationController
  def teleport_save
    model = Teleport_receiver.get_model

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
    model = Teleport_receiver.get_model
    entity = Teleport_receiver.get_entity

    key = params[entity]["__key"]
    @candidate = model.find(:first, :conditions => {:__key => key})
    @candidate.destroy unless @candidate == nil

    render :nothing => true
  end

  def teleport_create
    model = Teleport_receiver.get_model

    @candidate = model.new
    Teleport_receiver.convert_object(params, @candidate)

    if @candidate.save
      Logger.success
    else
      Logger.fail
    end

    render :nothing => true
  end
end
