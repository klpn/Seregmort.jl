module Seregmort

using JSONStat, Requests, DataStructures, DataFrames, PyCall, PyPlot
import JSON
@pyimport cartopy.io.shapereader as shpreader
@pyimport cartopy.crs as ccrs
export metadata, allregions, unchanged_regions, ndeaths, npop, munis_incounty,
propplot_dict, propplot, propscatsexes_dict, propscatsexes,propmap_dict, propmap, 
catot_yrsdict, capop_yrsdict, catot_mapdict, capop_mapdict,
threep, fourp, fivep

MORTURL = "http://api.scb.se/OV0104/v1/doris/sv/ssd/START/HS/HS0301/DodaOrsak"
POPURL = "http://api.scb.se/OV0104/v1/doris/sv/ssd/START/BE/BE0101/BE0101A/BefolkningNy"
DATAPATH = normpath(Pkg.dir(), "Seregmort", "data")
G_UNITS = JSON.parsefile(normpath(DATAPATH, "g_units.json"))

PyDict(matplotlib["rcParams"])["axes.formatter.use_locale"] = true
matplotlib[:style][:use]("ggplot")

function scb_to_unit(scb)
	scbform = *("SE/", rpad(scb, 9, 0))
	if scbform in keys(G_UNITS)
		return G_UNITS[scbform]
	else
		return 0
	end
end

function metadata(url = MORTURL)
	req = Requests.get(url)
	JSON.parse(Requests.readall(req), dicttype = DataStructures.OrderedDict)
end

function causealias(cause, dim)
	if cause == "POP"
		return lowercase(dim["ContentsCode"]["category"]["label"]["BE0101N1"])
	else
		return dim["Dodsorsak"]["category"]["label"][cause]
	end
end

regalias(region, dim) = lstrip(replace(dim["Region"]["category"]["label"][region], region, ""))

sexalias(sex, dim) = dim["Kon"]["category"]["label"][sex]

function agesplitter(age)
	if contains(age, "-")
	    return split(age, "-")
	else
	    return [age]
	end
end

function ageslice(startage, endage, agemean)
	ages = allages()
	startind = indexin([startage], ages)[1]
	endind = indexin([endage], ages)[1]
	if agemean
		agemeanstr = " medel över åldrar"
	else
		agemeanstr = ""
	end
	if startage == endage
		alias = *(replace(startage, "-", '\u2013'), agemeanstr)
	else
	    alias = *(agesplitter(startage)[1], "\u2013", agesplitter(endage)[end], agemeanstr)
	end
	agelist = ages[startind:endind]
	Dict("agelist" => agelist, "alias" => alias)
end

function allages(ageformat = "mort")
	if ageformat == "mort"
		startint = "0"
		startages = vcat(1, collect(5:5:85))
		endages = vcat(4, collect(9:5:89))
		endint = "90+"
	elseif ageformat == "pop"
		startint = "-4"
		startages = collect(5:5:95)
		endages = collect(9:5:99)
		endint = "100+"
	end
	midints = ["$x-$y" for (x, y) in zip(startages, endages)]
	vcat(startint, midints, endint)
end

function allregions(level, metadict)
	regvalues = metadict["variables"][1]["values"]
	if level == "county"
		return filter(is_county, regvalues)
	elseif level == "municipality"
		return filter(is_municipality, regvalues)
	end
end

unchanged_county(region) = !(region[1:2] in ["11"; "12"; "14"; "15"; "16"])
unchanged_regions(level, metadict) = filter(unchanged_county, allregions(level, metadict))

yearrange(startyear = 1969, endyear = 1996) = ["$(year)" for year in startyear:endyear]

is_county(region) = length(region) == 2 && region != "00"
is_municipality(region) = length(region) == 4

function munis_incounty(county, metadict)
	regvalues = metadict["variables"][1]["values"]
	filter((x) -> (is_municipality(x) && startswith(x, county)), regvalues)
end

function mortreqjson(regvalues, causevalues,  agevalues = allages(),
	sexvalues = ["1"; "2"], yearvalues = yearrange())
	if is_county(regvalues[1])
		regfilter = "vs:RegionLän"
	else
		regfilter = "vs:RegionKommun95"
	end
	if contains(causevalues[1], "-")
		causefilter = "agg:DödsorsakKapitel"
	else
		causefilter = "item"
	end

	Dict("response" => Dict("format" => "json-stat"),
		"query" => [
		Dict("selection" => Dict("filter" => regfilter, "values" => regvalues),
			"code" => "Region");
		Dict("selection" => Dict("filter" => causefilter, "values" => causevalues),
			"code" => "Dodsorsak");
		Dict("selection" => Dict("filter" => "item", "values" => agevalues),
			"code" => "Alder");
		Dict("selection" => Dict("filter" => "item", "values" => sexvalues),
			"code" => "Kon");
		Dict("selection" => Dict("filter" => "item", "values" => yearvalues),
			"code" => "Tid")
		]
		)
end

function popreqjson(regvalues, agevalues = allages("pop"),
	sexvalues = ["1"; "2"], yearvalues = yearrange())
	if is_county(regvalues[1])
		regfilter = "vs:RegionLän07"
	else
		regfilter = "vs:RegionKommun07"
	end

	Dict("response" => Dict("format" => "json-stat"),
		"query" => [
		Dict("selection" => Dict("filter" => regfilter, "values" => regvalues),
			"code" => "Region");
		Dict("selection" => Dict("filter" => "agg:Ålder5år", "values" => agevalues),
			"code" => "Alder");
		Dict("selection" => Dict("filter" => "item", "values" => sexvalues),
			"code" => "Kon");
		Dict("selection" => Dict("filter" => "item", "values" => ["BE0101N1"]),
			"code" => "ContentsCode");
		Dict("selection" => Dict("filter" => "item", "values" => yearvalues),
			"code" => "Tid")
		]
		)
end

function ndeaths(regvalues, causevalues;  agevalues = allages(),
	sexvalues = ["1"; "2"], yearvalues = yearrange())
	qjson = mortreqjson(regvalues, causevalues, agevalues, sexvalues, yearvalues)
	req = Requests.post(MORTURL, json = qjson)
	reqjsonstat = JSON.parse(Requests.readall(req),
		dicttype = DataStructures.OrderedDict)
	readjsonbundle(reqjsonstat)["dataset"]
end

function npop(regvalues; agevalues = allages("pop"),
	sexvalues = ["1"; "2"], yearvalues = yearrange())
	qjson = popreqjson(regvalues, agevalues, sexvalues, yearvalues)
	req = Requests.post(POPURL, json = qjson)
	reqjsonstat = JSON.parse(Requests.readall(req),
		dicttype = DataStructures.OrderedDict)
	readjsonbundle(reqjsonstat)["dataset"]
end

dfarrmatch(col, arr) = map((x) -> in(x, arr), Vector(col))

subframe_sray(df, sex, region, agelist, years) = df[((df[:Kon].==sex)
	& (df[:Region].==region) & (dfarrmatch(df[:Alder], agelist))
	& (dfarrmatch(df[:Tid], years))), :]

dfgrp(df, grpcol, f = sum) = by(df, grpcol, x -> DataFrame(value = f(x[:value])))

function grpprop(numframe_sub, denomframe_sub, grpcol, agemean)
	if agemean
		propfr_agesp = DataFrame()
		propfr_agesp[grpcol] = numframe_sub[grpcol]
		propfr_agesp[:value] = numframe_sub[:value]./denomframe_sub[:value]
		return dfgrp(propfr_agesp, grpcol, mean)
	else
		numgrp = dfgrp(numframe_sub, grpcol)
		denomgrp = dfgrp(denomframe_sub, grpcol)
		propfr_agegr = DataFrame()
		propfr_agegr[grpcol] = numgrp[grpcol]
		propfr_agegr[:value] = numgrp[:value]./denomgrp[:value]
		return propfr_agegr
	end
end

function prop_timegrp(numframe, denomframe, sex, region, agelist, years, agemean)
	numframe_sub = subframe_sray(numframe, sex, region, agelist, years)
	denomframe_sub = subframe_sray(denomframe, sex, region, agelist, years)
	grpprop(numframe_sub, denomframe_sub, :Tid, agemean)

end

propplotyrs_dict(startage, endage, pardict,
	agemean = false, years = yearrange(), sexes = ["2", "1"]) =
propplotyrs(pardict["numframe"], pardict["denomframe"], pardict["numdim"],
	pardict["denomdim"], pardict["numcause"], pardict["denomcause"], pardict["region"],
	startage, endage, agemean, years, sexes)

function propplotyrs(numframe, denomframe, numdim, denomdim, numcause, denomcause, 
        region, startage, endage, agemean, years, sexes)
	numcauseal = causealias(numcause, numdim)
	denomcauseal = causealias(denomcause, denomdim)
	regal = regalias(region, numdim)
	ages = ageslice(startage, endage, agemean)
	ageal = ages["alias"]
	agelist = ages["agelist"]
	yrints = map((x)->parse(Int, x), years)
	for sex in sexes
		sexal = sexalias(sex, numdim)
		propframe = prop_timegrp(numframe, denomframe, 
			sex, region, agelist, years, agemean) 
		plot(yrints, propframe[:value], label = sexal)
	end
	legend(framealpha = 0.5)
	xlim(yrints[1], yrints[end])
	ylim(ymin = 0)
	title("Döda $(numcauseal)/$(denomcauseal)\n$(ageal) $(regal)")
end

subframe_sa(df, sex, agelist) = df[((df[:Kon].==sex)
	& (dfarrmatch(df[:Alder], agelist))), :]

function prop_reggrp(numframe, denomframe, sex, agelist, agemean)
	numframe_sub = subframe_sa(numframe, sex, agelist)
	denomframe_sub = subframe_sa(denomframe, sex, agelist)
	grpprop(numframe_sub, denomframe_sub, :Region, agemean)
end

propscatsexes_dict(startage, endage, pardict, agemean = false) =
propscatsexes(pardict["numframe"], pardict["denomframe"], pardict["numdim"],
	pardict["denomdim"], pardict["numcause"], pardict["denomcause"],
	startage, endage, agemean)

function propscatsexes(numframe, denomframe, numdim, denomdim, numcause, denomcause, 
        startage, endage, agemean = false)
	numcauseal = causealias(numcause, numdim)
	denomcauseal = causealias(denomcause, denomdim)
	ages = ageslice(startage, endage, agemean)
	ageal = ages["alias"]
	agelist = ages["agelist"]
	yrints = map((x)->parse(Int, x), numframe[:Tid])
	startyear = minimum(yrints)
	endyear = maximum(yrints)
	sexframes = Dict()
	for sex in ["2", "1"]
		sexframes[sex] = Dict()
		sexframes[sex]["alias"] = sexalias(sex, numdim)
		sexframes[sex]["propframe"] = prop_reggrp(numframe, denomframe,
			sex, agelist, agemean)
	end
	femprop = sexframes["2"]["propframe"][:value]
	maleprop = sexframes["1"]["propframe"][:value]
	regcodes = sexframes["2"]["propframe"][:Region]
	regals = map((x)->regalias(x, numdim), regcodes)
	scatter(femprop, maleprop)
	for (i, regcode) in enumerate(regcodes)
		annotate(regcode, (femprop[i], maleprop[i]))
	end
	xlabel(sexframes["2"]["alias"])
	ylabel(sexframes["1"]["alias"])
	axminimum = 0.95
	axmaximum = 1.05
	xlim(minimum(femprop)*axminimum, maximum(femprop)*axmaximum)
	ylim(minimum(maleprop)*axminimum, maximum(maleprop)*axmaximum)
	title(*("Döda $(numcauseal)/$(denomcauseal)\n",
		"$(ageal) $(startyear)\u2013$(endyear)"))
	DataFrame(code = regcodes, alias = regals, femprop = femprop,
		maleprop = maleprop)
end

perc_round(value) = replace("$(round(value, 4))", ".", ",")

threep(prop) = 
	[
	Dict("col" => "lightsalmon", "value" => percentile(prop, 1/3*100));
	Dict("col" => "tomato", "value" => percentile(prop, 2/3*100));
	Dict("col" => "red", "value" => percentile(prop, 100))
	]

fourp(prop) = 
	[
	Dict("col" => "lightyellow", "value" => percentile(prop, 1/4*100));
	Dict("col" => "yellow", "value" => percentile(prop, 2/4*100));
	Dict("col" => "tomato", "value" => percentile(prop, 3/4*100));
	Dict("col" => "red", "value" => percentile(prop, 100))
	]

fivep(prop) = 
	[
	Dict("col" => "lightyellow", "value" => percentile(prop, 1/5*100));
	Dict("col" => "yellow", "value" => percentile(prop, 2/5*100));
	Dict("col" => "orange", "value" => percentile(prop, 3/5*100));
	Dict("col" => "tomato", "value" => percentile(prop, 4/5*100));
	Dict("col" => "red", "value" => percentile(prop, 100))
	]

propmap_dict(startage, endage, sex, pardict, percfunc = threep, agemean = false) =
propmap(pardict["numframe"], pardict["denomframe"], pardict["numdim"],
	pardict["denomdim"], pardict["numcause"], pardict["denomcause"],
	startage, endage, sex, pardict["shapefname"], percfunc, agemean)

function propmap(numframe, denomframe, numdim, denomdim, numcause, denomcause,
        startage, endage, sex, shapefname, percfunc = threep, agemean = false)
	numcauseal = causealias(numcause, numdim)
	denomcauseal = causealias(denomcause, denomdim)
	sexal = sexalias(sex, numdim)
	ages = ageslice(startage, endage, agemean)
	ageal = ages["alias"]
	agelist = ages["agelist"]
	yrints = map((x)->parse(Int, x), numframe[:Tid])
	startyear = minimum(yrints)
	endyear = maximum(yrints)
	region_shp = shpreader.Reader(shapefname)
	propframe = prop_reggrp(numframe, denomframe, sex, agelist, agemean)
	regcodes = propframe[:Region]
	regals = map((x)->regalias(x, numdim), regcodes)
	prop = propframe[:value]
	propdict = Dict(zip(regcodes, prop))
	units = map(scb_to_unit, regcodes)
	regdict = Dict(zip(units, regcodes))
	percentiles = percfunc(prop) 
	ax = plt[:axes](projection = ccrs.TransverseMercator())
	boundlist = []
	facecolor = "red"
	for region_rec in region_shp[:records]()
		regunit = region_rec[:attributes]["G_UNIT"]
		regend = region_rec[:attributes]["GET_END_YE"]
		if (regunit in keys(regdict) && regend > 1995)
			boundlist = vcat(boundlist, region_rec[:bounds])
			xmean = mean([boundlist[end][1];
				boundlist[end][3]])
			ymean = mean([boundlist[end][2];
				boundlist[end][4]])
			for percentile in percentiles
				if propdict[regdict[regunit]] <= percentile["value"]
					facecolor = percentile["col"]
					break
				end
			end
			ax[:add_geometries](region_rec[:geometry],
				ccrs.TransverseMercator(),
				edgecolor = "black", facecolor = facecolor)
			ax[:annotate](regdict[regunit], (xmean, ymean),
				ha = "center")
		end
	end
	xminimum = minimum([bound[1] for bound in boundlist])
	xmaximum = maximum([bound[3] for bound in boundlist])
	yminimum = minimum([bound[2] for bound in boundlist])
	ymaximum = maximum([bound[4] for bound in boundlist])
	ax[:set_xlim](xminimum, xmaximum)
	ax[:set_ylim](yminimum, ymaximum)
	percpatches = []
	perclabels = []
	for (i, percentile) in enumerate(percentiles)
		percpatch = matplotlib[:patches][:Rectangle]((0, 0), 1, 1,
			facecolor = percentile["col"])
		percpatches = vcat(percpatches, percpatch)
		if i == 1
			perclabel = *("\u2265", perc_round(minimum(prop)),
				"\n\u2264", perc_round(percentile["value"]))
		else
			perclabel = *("\u2264", perc_round(percentile["value"]))
		end
		perclabels = vcat(perclabels, perclabel)
	end
	legend(percpatches, perclabels, loc = "upper left", 
		framealpha = 0.75, bbox_to_anchor=(1,1))
	title(*("Döda $(numcauseal)/$(denomcauseal)\n",
		"$(sexal) $(ageal) $(startyear)\u2013$(endyear)"))
	subplots_adjust(right = 0.8)
	show()
	DataFrame(code = regcodes, alias = regals, prop = prop)
end

function catot_yrsdict(region, cause)
	cadeaths = ndeaths([region], [cause])
	totdeaths = ndeaths([region], ["TOT"])
	Dict(
		"numframe" => cadeaths["datasetframe"],
		"denomframe" => totdeaths["datasetframe"],
		"numdim" => cadeaths["dimension"],
		"denomdim" => totdeaths["dimension"],
		"numcause" => cause,
		"denomcause" => "TOT",
		"region" => region
	)
end

function capop_yrsdict(region, cause)
	cadeaths = ndeaths([region], [cause])
	pop = npop([region])
	Dict(
		"numframe" => cadeaths["datasetframe"],
		"denomframe" => pop["datasetframe"],
		"numdim" => cadeaths["dimension"],
		"denomdim" => pop["dimension"],
		"numcause" => cause,
		"denomcause" => "POP",
		"region" => region
	)
end

function catot_mapdict(regvalues, cause, startyear, endyear,
	shapefname = normpath(DATAPATH, "2504", "__pgsql2shp2504_tmp_table.shp"))
	cadeaths = ndeaths(regvalues, [cause],
		yearvalues = yearrange(startyear, endyear))
	totdeaths = ndeaths(regvalues, ["TOT"],
		yearvalues = yearrange(startyear, endyear))
	Dict(
		"numframe" => cadeaths["datasetframe"],
		"denomframe" => totdeaths["datasetframe"],
		"numdim" => cadeaths["dimension"],
		"denomdim" => totdeaths["dimension"],
		"numcause" => cause,
		"denomcause" => "TOT",
		"shapefname" => shapefname 
	)
end

function capop_mapdict(regvalues, cause, startyear, endyear,
	shapefname = normpath(DATAPATH, "2504", "__pgsql2shp2504_tmp_table.shp"))
	cadeaths = ndeaths(regvalues, [cause],
		yearvalues = yearrange(startyear, endyear))
	pop = npop(regvalues, yearvalues = yearrange(startyear, endyear))
	Dict(
		"numframe" => cadeaths["datasetframe"],
		"denomframe" => totdeaths["datasetframe"],
		"numdim" => cadeaths["dimension"],
		"denomdim" => totdeaths["dimension"],
		"numcause" => cause,
		"denomcause" => "POP",
		"shapefname" => shapefname 
	)
end

end # module
