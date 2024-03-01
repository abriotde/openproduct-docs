#!/usr/local/bin/julia --startup=no
#=
	Get and print statistics of website use according to web server logfiles
=#

using ArgParse
using GZip

DATA_PATH = "./data/"

regexLogFile = Regex("addon-openproduct.fr.kaja9241.odns.fr(-ssl_log)?-([A-Za-z]+)-([0-9]+).gz")
regexLogLine = Regex("(.*) -.*- \\[([0-9]+)/([A-Z][a-z]+)/([0-9]+).*\\].*")
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

#=
	Parse log file `filename` and generate a Dict with use statistics 
=#
function getStatsFromFile(filename, stats)
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
			end
		end
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
function getStats()
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

year = 0
# sync()
stats = getStats()
printStats(stats)
