#!/bin/env julia

#########  #############
# TODO : Get number of pages per regions.


import DBInterface, CSV
using ArgParse, DataFrames, Dates


function parse_commandline()
	s = ArgParseSettings(description = "This program load a CSV file (tab separated) of producers of OpenProduct in his database.")
	@add_arg_table s begin
	 "--area"
		 help = "Import a uniq departement."
		 arg_type = Int
    "csvFile"
        help = "The CSV file"
        required = true
	end
	return parse_args(s)
end
args = parse_commandline()

include("connect.jl")
dbConnection = OpenProduct.get_connection(ROOT_PATH)

function loadProducts(dbConnection)::Dict{String, Integer}
	products = Dict()
	sql="select id, name from products"
	pdcts = DBInterface.execute(dbConnection, sql)
	for product in pdcts
		products[product[2]] = product[1]
	end
	# println(products)
	products
end
products_by_name = loadProducts(dbConnection)

function add_product(dbConnection::LibPQ.DBConnection, producer_id::Integer, product_id::Integer)
	sqlInsertProduct = "Insert into producers_products(producer_id, product_id) values (\$1, \$2) \
		ON CONFLICT (producer_id, product_id) DO NOTHING;"
	DBInterface.execute(dbConnection, sqlInsertProduct, (producer_id, product_id))
end
function add_product(dbConnection::LibPQ.DBConnection, producer_id::Integer, product::String)
	product = lowercase(product)
	for p in split(product, ",")
		p = strip(p)
		if match(r"^[0-9]+$", p)!=nothing
			product_id = parse(Int, p)
			# TODO : Check this id is exists
		else
			product_id = get(products_by_name, p, 0)
			println("Add product ",p," (",product_id,")  to ", producer_id)
		end
		if product_id<=0
			println("Warning : product '",p,"' do not exists (on producer '", producer_id,"')")
		else
			add_product(dbConnection, producer_id, product_id)
		end
	end
end
#=

=#
function load_producer(line::DataFrameRow)::Bool
	# println("load_producer(",line,");")
	line2 = NamedTuple(line)
	# Identity
	company_name = get(line2, :company_name, missing)
	if ismissing(company_name)
		println("ERROR : ",company_name," : No required field 'company_name'")
		return false
	end
	firstname = get(line2, :firstname, "")
	lastname = get(line2, :lastname, "")
	sourcekey = imageurl = missing
	imageurl = missing
	# Position
	address = get(line2, :address, missing)
	postal_code = get(line2, :postal_code, missing)
	city = get(line2, :city, missing)
	latitude = get(line2, :latitude, missing)
	longitude = get(line2, :longitude, missing)
	email = phoneNumber = phoneNumber2 = missing
	score = 1.0
	if !ismissing(address) && !ismissing(postal_code) && !ismissing(city)
		# Even if latitude/longitude are sets, get correct ones.
		address_query = address*" "*string(postal_code)*" "*city
		latitude, longitude , score, postal_code, city, address = getXYFromAddress(address_query)
	elseif !ismissing(latitude) && !ismissing(longitude)
		latitude, longitude , score, postal_code, city, address = getAddressFromXY(latitude, longitude)
	end
	if ismissing(address) || ismissing(postal_code) || ismissing(city) ||
			ismissing(latitude) || ismissing(longitude)
		println("ERROR : ",company_name," : Can not accept producer without positionnal informations \
			 (latitude=",latitude,", longitude=",longitude,
			 " , postal_code=",postal_code,", city=",city,", address=",address,")")
		return false
	end
	# Contact
	email = get(line2, :email, missing)
	siret_number = get(line2, :siret_number, missing)
	website = []
	for n in 1:3
		website_value = get(line2, Symbol("website_"*string(n)), "")
		push!(website, website_value)
	end

	# Activity
	description = get(line2, :description, missing)
	shortDescription = get(line2, :category, missing)
	categories = "I"
	if ismissing(shortDescription) || ismissing(description)
		println("ERROR : ",company_name," : No required field 'description' (",description,") or 'category' (",shortDescription,")")
		return false
	end
	# Dates
	dateformater = dateformat"y-m-dTH:M:S"
	lastUpdateDate = now() # Dates.format(now(), dateformater)
	siret = openingHours = missing
	startdate = "1900-01-01"
	producer = OpenProductProducer(
		latitude, longitude, score, company_name, firstname, lastname, city, postal_code,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, description, sourcekey, imageurl, openingHours, categories, 
		startdate, missing, lastUpdateDate
	)
	# println(producer)
	producer_id = insertOnDuplicateUpdate(dbConnection, producer)
	if producer_id==1 # It was an insert, relaunch to update and get Id
		producer_id = insertOnDuplicateUpdate(dbConnection, producer)
	end
	println("Producer ",company_name," (n°", producer_id,")")
	production = get(line2, :production, missing)
	if producer_id>0 && !ismissing(production)
		add_product(dbConnection, producer_id, production)
	end
	true
end

function load_csv(filepath)
	println("load_csv(",filepath,")")
	df = CSV.read(filepath, DataFrame; header=2)
	colnames = Symbol[]
	for name in names(df)
		if startswith(name, "Nom du producteur")
			name = Symbol("company_name")
		elseif startswith(name, "Prénom")
			name = Symbol("firstname")
		elseif startswith(name, "Nom de famille")
			name = Symbol("lastname")
		elseif startswith(name, "Ville")
			name = Symbol("city")
		elseif startswith(name, "Code postal")
			name = Symbol("postal_code")
		elseif startswith(name, "Adresse")
			name = Symbol("address")
		elseif startswith(name, "Latitude")
			name = Symbol("latitude")
		elseif startswith(name, "Longitude")
			name = Symbol("longitude")
		elseif startswith(name, "n° de téléphone")
			name = Symbol("phone_number_1")
		elseif startswith(name, "2nd n° de téléphone")
			name = Symbol("phone_number_2")
		elseif startswith(name, "email")
			name = Symbol("email")
		elseif startswith(name, "Site web")
			name = Symbol("website_1")
		elseif startswith(name, "2nd site web")
			name = Symbol("website_2")
		elseif startswith(name, "3° site web")
			name = Symbol("website_3")
		elseif startswith(name, "Description")
			name = Symbol("description")
		elseif startswith(name, "Horaires d’ouvertures")
			name = Symbol("opening_hours")
		elseif startswith(name, "Catégorie")
			name = Symbol("category")
		elseif startswith(name, "Production")
			name = Symbol("production")
		elseif startswith(name, "Tag")
			name = Symbol("tag")
		elseif startswith(name, "Siret")
			name = Symbol("siret_number")
		else
			name = Symbol(name)
		end
		push!(colnames, name)
	end
	rename!(df, colnames)
	for line in eachrow(df)
		try
			load_producer(line)
		catch e
			println("ERROR : for producer ",line,"; ",e,"")
			Base.showerror(stdout, e, Base.catch_backtrace())
		end
	end
	# println(df)
end



load_csv(args["csvFile"])

DBInterface.close!(dbConnection)

