#!/usr/local/bin/julia
using ArgParse

######### https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/entreprises-du-patrimoine-vivant-epv/exports/csv?lang=fr&timezone=Europe%2FParis&use_labels=true&delimiter=%3B #############
# TODO : Get number of pages per regions.


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, CSV, JSON, URIs
using DataFrames, Dates

using Cascadia


areas = Dict(
)
regexIdProducer = Regex("producteur([0-9]+)")

include("connect.jl")
using .OpenProduct

function parse_commandline()
	s = ArgParseSettings()
	@add_arg_table s begin
	 "--area"
		 help = "Import a uniq departement."
		 arg_type = Int
	 "--all", "-a"
		 help = "Import all departements (default none)."
		 action = :store_true
	end
	return parse_args(s)
end
categoriesByUnivers = Dict(
	"Gastronomie" => "A",
	"Culture et Communication" => "",
	"Equipements Industriels, Médicaux, Mécaniques" => "",
	"Ameublement et Décoration" => "O0",
	"Architecture et Patrimoine Bâti" => "OU",
	"Architecture et Patrimoine bâti" => "OU",
	"Mode et beauté" => "OB",
	"Loisirs et Transports" => "OU",
	"Arts de la table" => "OQ",
	"Fournitures, Équipements et Matériaux" => "O",
	"Sports et Activités de plein air" => "",
	"Musique" => "O5",
)
#=
=#
function parse_producers()
    nbProducers = 0
    # try
        tmpfile = "./parse_entreprises_du_patrimoine_vivant.csv"
        url = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/entreprises-du-patrimoine-vivant-epv/exports/csv?lang=fr&timezone=Europe%2FParis&use_labels=true&delimiter=%3B"
		# println("Download ", url); download(url,tmpfile); println("Download done")
		lines = CSV.read(tmpfile, DataFrame; delim=';', header=true)
        # response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml

	    # Iterate over <div id="producteur2201" class="col-12">
	    for producer in eachrow(lines)
			# Raison sociale;SIRET;Code NAF;Libellé NAF;Région;Date de labellisation;Date de fin de labellisation;Univers;geolocetablissement
			# println("Producer:", producer)
			coordonnates = split(producer[:geolocetablissement], ",")
			lat = parse(Float64,coordonnates[1])
			lon = parse(Float64,coordonnates[2])
			_, _, score, postcode, city, address = getAddressFromXY(lat, lon)
			if city==""
				println("WARNING : No address found for producer ", producer)
				city = string(producer."Région")
				address = string(producer."Région")
				postcode = 01111
			end
			# Convert types to match OpenProductProducer constructor
			univers = string(producer[:Univers])
			categorie = ""
			for uni in split(univers, [';'])
				categorie = get(categoriesByUnivers, uni, "_")
				if categorie == "_"
					println("Producer:", producer)
					println("WARNING : Unknown univers '", uni, "' for producer SIRET=", producer[:SIRET])
					exit(0)
				end
				if categorie!=""
					break
				end
			end
			producerObj = OpenProductProducer(
				lat, lon, score, string(producer."Raison sociale"), "", "", 
				string(city), postcode, string(address),
				"", "", string(producer[:SIRET]), "", "",
				univers, string(producer."Libellé NAF"), "", categorie, "", "", now()
			)
			nbProducers += 1
			if categorie!=""
				insertOnDuplicateUpdate(producerObj, forceInsert=true)
			end
			print(".")
	    end
		println("Nb producers : ", nbProducers)
	    nbProducers
    # end
end


args = parse_commandline()
parse_producers()

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(dbConnection)

exit()
