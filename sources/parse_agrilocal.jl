#!/bin/env julia

######### https://cotesdarmor.fr/actualites/une-carte-pour-consommer-local #############

# import Pkg; Pkg.add("JSON")
# import Pkg; Pkg.add("MySQL")
import JSON, MySQL, DBInterface


# download("https://agrilocal22.gogocarto.fr/api/elements?bounds=-3.85071%2C48.08909%2C-1.7276%2C49.12422%3B&boundsJson=%5B%7B%22_southWest%22%3A%7B%22lat%22%3A48.08909%2C%22lng%22%3A-3.85071%7D%2C%22_northEast%22%3A%7B%22lat%22%3A49.12422%2C%22lng%22%3A-1.7276%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%5D"
#     ,"./agrilocal.json"
# )


conn = DBInterface.connect(MySQL.Connection, "Localhost", "root", "osiris")
sqlInsert = DBInterface.prepare(conn, "Insert ignore into openproduct.producer
 (latitude, longitude, name, city, postCode, address, phoneNumber, siret, email, website, `text`, openingHours)
 values (?,?,?,?,?,?, ?,?,?,?,?,?) on duplicate key update postCode=values(postCode)")

jsonStr = read("agrilocal.json", String)
datas = JSON.parse(jsonStr)
producers = datas["data"]
sep = ";"
NULL_VALUE = ""

function getVal(dict, key, default_value)
    if haskey(dict, key)
        dict[key]
    else
        default_value
    end

end

# latitude, longitude, name,
#   city, postCode, address,
#   phoneNumber, siret,
#   email, website, `text`, openingHours

for producer in producers
    print(".")
    geo = producer["geo"]

    address = producer["address"]
    addressDetail = getVal(address, "customFormatedAddress", NULL_VALUE)
    postalCode = getVal(address, "postalCode", NULL_VALUE)

    openingHours = haskey(producer, "precisions_sur_les_diffentes_ventes") ? producer["precisions_sur_les_diffentes_ventes"] : NULL_VALUE
    siret = getVal(producer, "siret", NULL_VALUE)
    description = getVal(producer, "description", NULL_VALUE)
    website = NULL_VALUE
    if haskey(producer, "site_internet")
        website = producer["site_internet"]
    elseif haskey(producer, "page_facebook")
        website = producer["page_facebook"]
    end
    phoneNumber = NULL_VALUE
    if haskey(producer, "telephone")
        phoneNumber = producer["telephone"]
    elseif haskey(producer, "mobile")
        phoneNumber = producer["mobile"]
    end


    # println(string(geo["latitude"])*sep*string(geo["longitude"])*sep*producer["name"]*sep
    #     *address["addressLocality"]*sep*postalCode*sep*addressDetail*sep
    #     *phoneNumber*sep*siret
    #     *sep*producer["email"]*sep*website*sep*description*sep*openingHours
    # )

    values = [
        geo["latitude"], geo["longitude"], producer["name"],
        address["addressLocality"], postalCode, addressDetail
        , phoneNumber, siret, producer["email"]
        , website, description, openingHours
    ]
    println(values)
    DBInterface.execute(sqlInsert, values)

end
println(".")

DBInterface.close!(conn)
