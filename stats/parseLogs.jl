#!/bin/env julia
#=
	Get and print statistics of website use according to web server logfiles
=#
import DBInterface, LibPQ
using ArgParse
using GZip

DATA_PATH = "./data/"

regexLogFile = Regex("addon-openproduct.fr.kaja9241.odns.fr(-ssl_log)?-([A-Za-z]+)-([0-9]+).gz")
regexLogLine = Regex("(.*) -.*- \\[([0-9]+)/([A-Z][a-z]+)/([0-9]+).*\\].*")
regexLogLine = Regex("(.*) -.*- \\[([0-9]+)/([A-Z][a-z]+)/([0-9]+).*\\] \"GET ([a-zA-Z/.]+).*\"(.*)\"")
MonthTranslation = Dict{String, Int}(
	"Jan" => 1,
	"Feb" => 2,
	"Mar" => 3,
	"Apr" => 4,
	"May" => 5,
	"Jun" => 6,
	"Jul" => 7,
	"Aug" => 8,
	"Sep" => 9,
	"Oct" => 10,
	"Nov" => 11,
	"Dec" => 12
)

monthVisitors = Dict{Integer,Dict{String, Bool}}()
#=
	Get log files from webserver
=#
function sync()
	if !isdir(DATA_PATH)
		mkdir(DATA_PATH)
	end
	run(`rsync -avpzh "openproduct:logs/addon-openproduct.fr.kaja9241.*" $DATA_PATH`)
end

botPatterns = ["bingbot","Googlebot","AhrefsBot"]

#=
	Parse log file `filename` and generate a Dict with use statistics 
=#
function getStatsFromFile(filename, stats)
	useragents = Dict{String, Int}()
	visitors = dateRef = monthStr = yearStr = month_i = month_i = nothing
	fd = GZip.open(DATA_PATH*"/"*filename, "r") do io
		linenb = 0
		while (line = readline(io))!=""
			# println("Line:",line)
			linenb += 1
			m = match(regexLogLine, line)
			if m!=nothing
				# println(m)
				ip = m[1]
				date = m[2]
				url = m[5]
				useragent = m[6]
				isbot = false
				for bot in botPatterns
					if occursin(bot, useragent)
						isbot = true
						useragent = bot
						# println("User-Agent:", useragent)
						break
					end
				end
				nbOccurUA = get(useragents, useragent, 0) + 1
				useragents[useragent] = nbOccurUA
				if isbot
					continue
				end
				useragents[useragent] = nbOccurUA
				# println("URL:", url,"; User-Agent:", useragent)
				if dateRef==nothing
					# Init for next dates
					visitors = Dict{String, Bool}()
					dateRef = date
					monthStr = m[3]
					yearStr = m[4]
					month_i = MonthTranslation[monthStr]
					if !haskey(monthVisitors, month_i)
						monthVisitors[month_i] = Dict{String, Bool}()
					end
				elseif dateRef!=date
					# Save values
					date_i = parse(Int64, dateRef)
					if !haskey(stats, month_i)
						stats[month_i] = Dict{Int, Int}()
					end
					val = length(visitors)
					if haskey(stats[month_i], date_i)
						val += stats[month_i][date_i]
					end
					stats[month_i][date_i] = val
					# Init for next dates
					visitors = Dict{String, Bool}()
					dateRef = date
					monthStr = m[3]
					yearStr = m[4]
					month_i = MonthTranslation[monthStr]
					if !haskey(monthVisitors, month_i)
						monthVisitors[month_i] = Dict{String, Bool}()
					end
				end
				# print(".")
				visitors[ip] = true
				monthVisitors[month_i][ip] = true
			# else
			# 	println("Skip : ", line)
			end
		end
		# println("User-Agents: ", useragents)
		# Save values
		date_i = parse(Int64, dateRef);
		if !haskey(stats, month_i)
			stats[month_i] = Dict{Int, Int}()
		end
		val = length(visitors)
		if haskey(stats[month_i], date_i)
			val += stats[month_i][date_i]
		end
		stats[month_i][date_i] = val
		# println()
	end
	stats
end

#=
	Parse all log files in `DATA_PATH` and return  a Dict with use statistics 
=#
function getStats()::Dict{Int,Dict{Int, Int}}
	stats = Dict{Int,Dict{Int, Int}}()
	for filename in readdir(DATA_PATH)
		println("File : ",filename)
		m=match(regexLogFile, filename)
		if m!=nothing
			month = m[2]
			global year = m[3]
			# println("Year:",year)
			getStatsFromFile(filename, stats)
			# println("stats : ",stats)
		else
			println("Error : file ",filename," not match")
		end
	end
	stats
end

#=
	Print human readable `stats` Dict of website use according to logfiles
=#
function printStats(stats)
	for month in 1:12
		if haskey(stats, month)
			println("Month:",month)
			monthStats = stats[month]
			for day in 1:31
				if haskey(monthStats, day)
					println(day,"/",month,"/",year," => ",monthStats[day])
				end
			end
			println("For month : ",length(monthVisitors[month]))
		end
	end
end
#=
	Load `stats` in PostgreSQL DB
=#
function loadStats(dbConnection::LibPQ.DBConnection, stats::Dict{Int,Dict{Int, Int}})::Bool
	sql = "Insert into stats_day(date, website_uniq_visit) VALUES (\$1, \$2) ON CONFLICT (date) DO UPDATE SET website_uniq_visit=EXCLUDED.website_uniq_visit;"
	sqlInsert = DBInterface.prepare(dbConnection, sql)
	for (month, values) in stats
		for (day, v) in values
			date = year*"-"*string(month)*"-"*string(day)
			LibPQ.execute(sqlInsert, (date, v))
			# println("Month:", month, "; Day:", day,"; Values:",v)
		end
	end
	true
end

year = 0
include("connect.jl")
dbConnection = OpenProduct.get_connection(ROOT_PATH)
if ENV=="dev"
	sync()
else
	DATA_PATH = "/home/kaja9241/logs"
end
stats = getStats()
printStats(stats)
# print("ENV:", ENV)
# loadStats(dbConnection, stats)
