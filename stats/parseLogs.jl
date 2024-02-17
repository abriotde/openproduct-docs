#!/usr/local/bin/julia --startup=no
#=
	Get and print statistics of website use according to web server logfiles
=#

using ArgParse
using GZip

DATA_PATH = "./data/"

regexLogFile = Regex("addon-openproduct.fr.kaja9241.odns.fr(-ssl_log)?-([A-Za-z]+)-([0-9]+).gz")
regexLogLine = Regex("(.*) -.*- \\[([0-9]+)/.*\\].*")
MonthTranslation = Dict(
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
function getStatsFromFile(filename)
	stats = Dict()
	dateRef = nothing
	fd = GZip.open(DATA_PATH*"/"*filename, "r") do io
		visitors = Dict()
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
					dateRef = date
					# println("Date:",date)
				elseif dateRef!=date
					# println("Date change:",date)
					val = length(visitors)
					date_i = parse(Int64, dateRef);
					stats[date_i] = val
					dateRef = date
					visitors = Dict()
				end
				visitors[ip] = true;
			end
		end
	end
	stats
end

#=
	Parse all log files in `DATA_PATH` and return  a Dict with use statistics 
=#
function getStats()
	stats = Dict()
	for filename in readdir(DATA_PATH)
		println("File : ",filename)
		m=match(regexLogFile, filename)
		if m!=nothing
			month = m[2]
			global year = m[3]
			# println("Year:",year)
			month_i = MonthTranslation[month]
			monthStats = getStatsFromFile(filename)
			if !haskey(stats, month_i)
				stats[month_i] = monthStats
			else
				# Concatenate results of multi-files (https && http)
				monthStats0 = stats[month_i]
				for day in 1:31
					val = 0
					if haskey(monthStats, day)
						val = monthStats[day]
					end
					if haskey(monthStats0, day)
						val += monthStats0[day]
					end
					if val>0
						stats[month_i][day] = val
					end
				end
			end
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
		end
	end
end

year = 0
sync()
stats = getStats()
printStats(stats)
