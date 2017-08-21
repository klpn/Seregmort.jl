# Seregmort 

[![Build Status](https://travis-ci.org/klpn/Seregmort.jl.svg?branch=master)](https://travis-ci.org/klpn/Seregmort.jl)

[![Coverage Status](https://coveralls.io/repos/klpn/Seregmort.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/klpn/Seregmort.jl?branch=master)

[![codecov.io](http://codecov.io/github/klpn/Seregmort.jl/coverage.svg?branch=master)](http://codecov.io/github/klpn/Seregmort.jl?branch=master)

This package can be used to analyze cause-specific regional Swedish mortality
data at county or municipality level using the Statistics Sweden API ([API
documentation in
English](http://www.scb.se/Grupp/OmSCB/API/API-description.pdf)). The database
accessible via the API covers deaths from 1969 to 1996 (a database covering
cause-specific deaths at the county level occurring since 1997 is publicly
accessible via [The National Board of Health and
Welfare](http://www.socialstyrelsen.se/statistik/statistikdatabas/dodsorsaker)
but cannot be used with the API). The package is a reimplementation in Julia of
[seregmort](https://github.com/klpn/seregmort), which is written in Python.

Data are retrieved in the [JSON-stat format](http://json-stat.org/) and saved
into Julia DataFrames using the [JSONStat](https://github.com/klpn/JSONStat.jl)
package.

The package uses grouping functions from my
[Mortchartgen](https://github.com/klpn/Mortchartgen.jl) package. You can
install that package e.g. by
`Pkg.clone("https://github.com/klpn/Mortchartgen.jl.git")`.

Possible values for regions, age groups, sexes and causes of death can be retrieved by `metadata()` which sends a GET request to the [mortality table](http://api.scb.se/OV0104/v1/doris/sv/ssd/START/HS/HS0301/DodaOrsak).

If the cause of death given contains a hyphen, it is assumed to be a chapter
rather than a single cause of death (the `agg:DödsorsakKapitel` level). The
following multi-cause chapters are supported:

| Chapter | Description
| ------- | -----------
| 1-2 | Infections
| 3-16 | Tumors
| 17-18 | Endocrine disorders
| 20-21 | Mental disorders
| 23-28 | Circulatory disorders
| 29-32 | Respiratory disorders
| 33-35 | Digestive disorders
| 36-39 | Genitourinary disorders
| 44-45 | Ill-defined causes
| 46-52 | External causes

## Examples
Save data on deaths from circulatory disorders in Västmanland County for the
whole period in a dictionary, and plot a smoothed diagram showing the time
trend for proportion of deaths due to this cause group for females and males in
age intervals above 70 years:

```julia
using Seregmort
pardict = catot_yrsdict("19", "23-28")
propplotyrs_dict("70-74", "90+", pardict)
```
Save data on deaths from circulatory disorders in all municipalities in
Norrbotten County for the period 1981--86, and make a scatterplot of female vs
male proportion of all deaths due to this cause group during the period in the
age intervals between 75--79 and 85--89 years: 
```julia
pardict = catot_mapdict(munis_incounty("25", metadata()), "23-28", 1981, 1986)
propscatsexes_dict("75-79", "85-89", pardict)
```
Note that data for single years and narrow age bands are often not very useful due to the small numbers of deaths, especially at the municipality level.

Using [cartopy](https://github.com/SciTools/cartopy), it is also possible to plot maps showing regions with a lower or higher proportion of deaths from a given cause. 

The script has been adapted to work with the shapefiles available (under a
CCZero license) from National Archives of Sweden. You may download a [ZIP
archive](http://riksarkivet.se/psi/NAD_Topografidata.zip) with these files and
unzip it in the directory `data` under the main `Seregmort` directory. Data from
[one of the Excel metadata files](http://riksarkivet.se/psi/g_units_names.xls)
is included in this repository in JSON format (under `data`); this file is used
to translate the geographical codes used by Statistics Sweden into the unit
codes used in the shapefiles.

Plot a map of the proportion of female deaths due to circulatory disorders in
all municipalities in Västernorrland County during the period 1981--86 in the
age intervals between 75--79 and 85--89 years (note that
`data/2504/__pgsql2shp2504_tmp_table.shp` is default shapefile path):
```julia
pardict = catot_mapdict(munis_incounty("22", metadata()), "23-28", 1981, 1986)
propmap_dict("75-79", "85-89", "2", pardict)
```

By default, maps are plotted with three percentiles with different shades. You
can call the functions `fourp` and `fivep` to plot with four or five
percentiles instead. To plot a map of proportion of deaths due to ischemic
heart disease for all counties and all ages during the period 1981--86 among
males with five percentiles:
```julia
pardict = catot_mapdict(allregions("county", metadata()), "25", 1981, 1986)
propmap_dict("0", "90+", "1", pardict, fivep)
```

There is limited support for visualizing mortality rates by using population
size in the denominator (based on data from a [population
table](http://api.scb.se/OV0104/v1/doris/sv/ssd/START/BE/BE0101/BE0101A/BefolkningNy).
However, this is difficult to implement fully, because the tables use differing
age formats and (more importantly) because the population table uses a newer
regional division. Currently, it should work for age groups between 5--9 and
85--89 years and regions which have not changed since 1996. For example, to
plot a map of male mortality rates from circulatory disorders in the municipalities
in Västerbotten County during the period 1981--86 in the age intervals between
50--54 and 70--74 years:
```julia
pardict = capop_mapdict(munis_incounty("24", metadata(morturl)), "23-28", 1981, 1986)
propmap_dict("50-54", "70-74", "1", pardict)
```

The `capop_mapdict` wrapper can also be used with `propscatsexes_dict` for drawing
scatterplots, as in the example with `catot_mapdict`. The `capop_yrsdict`
wrapper can be used with `propplotyrs_dict`.

The `unchanged_regions` function can be used to selection those counties which
have remained unchanged. To plot a map of female mortality rates from circulatory
disorders in all counties, except for the changed ones in what is nowadays
Skåne and Västra Götaland County, during the period 1981--86 in the age intervals
65--69 and 70--74 years:
```julia
pardict = capop_mapdict(unchanged_regions("county", metadata()), "23-28", 1981, 1986)
propmap_dict("65-69", "70-74", "2", pardict)
```

Death rates may be influenced by the age structure of a population, which may
give misleading results, especially if wide age bands are compared. Because of
this, it is possible to calculate average death rates over 5-year age
intervals, by setting the argument `agemean` to `true`, for example:
```julia
pardict = capop_mapdict(unchanged_regions("county", metadata()), "23-28", 1981, 1986)
propmap("15-19", "70-74", "2", fivep, true)
```
