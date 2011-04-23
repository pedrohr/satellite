require "pp"

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
  #hash: {satelite_attribute => teleport_attribute}
  #TODO: this mapping should be created automatically
  @@mapping = {
    "occupation" => "occupation",
    "address" => "address",
    "name" => "name",
    "phone" => "phone"}

  #Satellite param
  @@key = "name"
    
  #TODO: handle nil cases
  def self.mapper(val)
    return @@mapping[val]
  end

  #Insert 'params' hash into some target object attributes
  #Ex.: All the attributes of the target object will be 
  #     filled with 'Person' under the mapping of 
  #     attributes
  def self.convert_params(params, target)
    info = params["Person"]
    hash = target.attributes

    hash.each do |key,value|
      target[key] = info[mapper(key)]
    end

    target["__key"] = params["Person"]["__key"]
    
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
    @candidate = Candidate.find(:first, :conditions => {:__key => params["__key"]})
    
    unless @candidate == nil
      params["update"].each{ |k,v|
        @candidate[k] = v
      }
      @candidate.save
    end

    render :nothing => true
  end

  def teleport_destroy
    key = params["Person"]["__key"]
    @candidate = Candidate.find(:first, :conditions => {:__key => key})
    @candidate.destroy unless @candidate == nil

    render :nothing => true
  end

  def teleport_create
    @candidate = Candidate.new
    Teleport_receiver.convert_object(params, @candidate)

    if @candidate.save
      Logger.success
    else
      Logger.fail
    end

    render :nothing => true
  end

  # GET /candidates
  # GET /candidates.xml
  def index
    @candidates = Candidate.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @candidates }
    end
  end

  # GET /candidates/1
  # GET /candidates/1.xml
  def show
    @candidate = Candidate.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @candidate }
    end
  end

  # GET /candidates/new
  # GET /candidates/new.xml
  def new
    @candidate = Candidate.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @candidate }
    end
  end

  # GET /candidates/1/edit
  def edit
    @candidate = Candidate.find(params[:id])
  end

  # POST /candidates
  # POST /candidates.xml
  def create
    @candidate = Candidate.new(params[:candidate])

    respond_to do |format|
      if @candidate.save
        format.html { redirect_to(@candidate, :notice => 'Candidate was successfully created.') }
        format.xml  { render :xml => @candidate, :status => :created, :location => @candidate }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @candidate.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /candidates/1
  # PUT /candidates/1.xml
  def update
    @candidate = Candidate.find(params[:id])

    respond_to do |format|
      if @candidate.update_attributes(params[:candidate])
        format.html { redirect_to(@candidate, :notice => 'Candidate was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @candidate.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /candidates/1
  # DELETE /candidates/1.xml
  def destroy
    @candidate = Candidate.find(params[:id])
    @candidate.destroy

    respond_to do |format|
      format.html { redirect_to(candidates_url) }
      format.xml  { head :ok }
    end
  end
end
