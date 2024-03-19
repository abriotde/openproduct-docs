#!/usr/local/bin/julia
using ArgParse
import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs
using Cascadia
DEBUG = false

# https://www.societe.com/cgi-bin/search?champs=827977281

include("connect.jl")

API_URL="https://api.pappers.fr/v2/"
API_TOKEN="f31cc367337907d63b68f8c8e5e022c8b41a0572b7043451"

function geSocieteInfos(firstname::String, lastname::String)
	url = API_URL*"recherche"*"?api_token="*API_TOKEN*"&q="*lastname*"%20"*firstname
end
#=
=#
function geSiretInfos(siret::String)
	len = length(siret)
	if len>9
		siren = siret[1:9]
	elseif len==9
		siren = siret
	else
		println("Error : Siret=",siret," is invalid : to short.")
		return ["","","",""]
	end
	tmpfile = "./societe.html"
	url = API_URL*"entreprise"*"?api_token="*API_TOKEN*"&siren="*siren
	println("Url:",url)
	# download(url,tmpfile); jsonStr = read(tmpfile, String);
	response = HTTP.get(url, timeout=30, status_exception=false)
	if response.status!=200
		if response.status==404
			println("=> ",response.status, "; URL:",url)
			return [missing, "{'ERROR':"*string(response.status)*"}"]
		else
			println("=> ",response.status, "; URL:",url)
			exit(0)
		end
	end
	jsonStr = response.body |> String
	datas = JSON.parse(jsonStr)
	producer = OpenProductProducer()
    producer.startdate = datas["date_creation"]
    enddate = datas["date_cessation"]
	if enddate!==nothing || datas["entreprise_cessee"]
		println("No siret=",siret," : ", producer.enddate,"; ",datas["entreprise_cessee"])
		producer.enddate = enddate
	end
	producer.name = datas["nom_entreprise"] # datas["denomination"]
	# Get address
	buildings = datas["etablissements"]
	for building in buildings
		address = building["adresse_ligne_1"]
		v = building["adresse_ligne_2"]
		if v!==nothing
			address *= v
		end
		producer.address = address
		producer.postCode = building["code_postal"]
		producer.city = building["ville"]
		producer.lat = building["latitude"]
		producer.lon = building["longitude"]
		producer.name = getKey(building, ["enseigne","nom_commercial"], producer.name)
	end
	# Get firstname/lastname
	people = datas["representants"] # "qualite": "Gérant"
	for man in people
		if man["qualite"]=="Gérant"
			producer.lastname = man["nom"]
			producer.firstname = man["prenom"]
		end
	end
	producer.text = datas["objet_social"]
	for d in datas["conventions_collectives"]
		producer.shortDescription = d["nom"]
	end
	producer.score = 0.9
	[producer, jsonStr]
end
function updateWebsiteStatus(id, websiteStatus)
	sql2 = "UPDATE producer SET websiteStatus='"*websiteStatus*"' WHERE id="*string(id)
	println("SQL:",sql2,";")
	# DBInterface.execute(dbConnection, sql2)
end
function testSirets()
	sql = """SELECT *
			FROM producer 
			WHERE siret IS NOT NULL AND siret NOT IN ('','0')
				AND siretStatus is NULL
				AND status!='hs'
				-- AND  (sendEmail IS NULL OR sendEmail='wrongEmail')
				-- AND websiteStatus in ('unknown','ConnectionError')
			ORDER BY ID
			LIMIT 15
		"""
	res = DBInterface.execute(dbConnection, sql)
	for params in res
		id = params[:id]
		name = params[:name]
		siret = params[:siret]
		producer, jsonStr = geSiretInfos(siret)
		println(" - ", name, " : ", producer)
		if producer===missing
			siretStatus = "ko"
		else
			if producer.enddate==""
				siretStatus = "ok"
			else
				siretStatus = "ko"
			end
			producerDB = Dict(propertynames(params) .=> values(params))
			update(producerDB, producer)
		end
		sql = "UPDATE producer SET siretStatus='"*siretStatus*"', companyInfos=\""*MySQL.escape(dbConnection, jsonStr)*"\" WHERE id="*string(id)
		println("SQL:",sql,";")
		println(" - ", name, " : ", producer," : ", siretStatus)
		# res2 = DBInterface.execute(dbConnection, sql)
	end
end

testSirets()


DBInterface.close!(dbConnection)
