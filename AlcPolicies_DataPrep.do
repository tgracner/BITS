/* ************************************************************************** */
/* PROJECT: ALCOHOL CONSUMPTION   											  */
/* THIS do-file: Preparation of alcohol-related policies over time 			  */
/* Prepared by: Tadeja Gracner, Summer 2018								      */
/* ************************************************************************** */


*------------------------------------------------------------------------------
*PREFERENCES
*------------------------------------------------------------------------------ 
clear
capture log close
set more off
set seed 1302
set matsize 10000

*------------------------------------------------------------------------------
*DIRECTORIES
*------------------------------------------------------------------------------

* change your local and global accordingly 
local TG "Desktop/OneDrive - Rand Corporation/Alc_Tobacco_NN"

* add your locals here and change it below

global in_files "~/`TG'/nicosia_alcohol/DATA/In"
global out_files "~/`TG'/nicosia_alcohol/DATA/Out"
global tables "~/`TG'/nicosia_alcohol/TABLES/tables"
global graphs "~/`TG'/nicosia_alcohol/FIGURES/figures"
global tex "~/`TG'/nicosia_alcohol/TEX"

************************** ALCOHOL POLICIES  **********************************

*** states from excel into stata.dta

import excel "$in_files/state_list_abr2.xlsx", sheet("state_abr") firstrow clear
keep state_name state_abr
drop if state_abr == ""

saveold "$out_files/state_abr.dta", replace

*** add abbreviations to state sales data
forvalues x = 2000(1)2013 {
import excel "$in_files/taxes/State_sales_taxes.xlsx", sheet("`x'") firstrow clear
	keep state_name salestax
	destring salestax, force replace
	drop if state_name == ""
	merge 1:1 state_name using "$out_files/state_abr.dta"
	drop _merge
	gen year = `x'
		save "$out_files/state_sales_taxes_abr_`x'.dta", replace
}

use "$out_files/state_sales_taxes_abr_2000.dta"
	forvalues x = 2001(1)2013{
	append using "$out_files/state_sales_taxes_abr_`x'.dta"
	}
save "$out_files/state_sales_taxes_all.dta", replace


*** all years and quarters from excel into stata.dta

import excel "$in_files/state_list_abr2.xlsx", sheet("year_all") firstrow clear
saveold "$out_files/years_1998_2016_quarters.dta", replace

* combine and create a matrix

use "$out_files/state_abr.dta", clear
gen expander = 80
expand expander
/* Now you should have 60 observations for each state */
drop expander

bysort state_abr: gen index = _n

/* COMPUTE QUARTERS */
gen temp = mod(index,4)

gen quarter = temp
    replace quarter = 4 if temp==0
    drop temp

gen temp = quarter == 1
    replace temp =0 if temp==1 & index==1
    bysort state_abr: gen running_sum_of_first_quarter = sum(temp)
    drop temp

gen temp_year = 1998
gen year = temp_year + running_sum_of_first_quarter


keep state_abr year quarter	

rename year year_start 
rename quarter quarter_start 

/*
tostring year, gen(year_start) format(%17.0g)

tostring quarter, gen(quarter_start) format(%17.0g)
*/

saveold "$out_files/states_years_1998_2016_quarters_all.dta", replace


*------------------------------------------------------------------------------
*  Driving priveledges - added Oct.9th
*------------------------------------------------------------------------------


import excel "$in_files/driving.xlsx", sheet("Sheet1") firstrow clear

drop if up_age_limit == .

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations

* identify start dates of policy changes 

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"
	

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before policy change"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

		
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq
		
		egen year_max = max(year_end), by(juri) // all policies last until 1/1/2017 in the end.
		
		
* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)

*tsset juri  year_quarter_start2  
bysort juri: gen time = _n
tsset juri time

tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .

* calculate "study quarters" - 80 for each state.
*bysort juri: gen time = _n


* obtain state abbreviations so you can merge datasets on them
gen str11 state_abr = substr(Jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start
drop time
bysort state_abr: gen time = _n

* replace missing values that happen due to data expansion above 
sort state_abr year_start quarter_start
foreach m in days  up_age_limit {
bysort state_abr: replace `m' = `m'[_n-1] if `m'== . 
}

foreach l in violation_purcase violation_possession violation_consumption authority_license suspend_min suspend_max citations {
bysort state_abr: replace `l' = `l'[_n-1] if `l' == ""
}


* put all variables lower care
rename *, lower

* drop variables we do not need for now
drop year_quarter_start2 _fillin dailydate2 dailydate1 year_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter


* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change daterange state_abr year quarter

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
	
gen no_change20032007 = (daterange == "1/1/2003 - 1/1/2017")
	label var no_change20032007 "No change in policy btw 2003 and 2017"
	
	drop if state_abr == ""
	
	drop if year == . 

** replace violations with "No" if empty.
rename violation_purcase violation_purchase 
replace violation_purchase = "No" if violation_purchase == ""
replace violation_possession = "No" if violation_possession == ""
replace violation_consumption = "No" if violation_consumption == ""

	saveold "$out_files/driving_privileges.dta", replace
	
	
*------------------------------------------------------------------------------
*  Underage vehicle operator - added Oct.9th
*------------------------------------------------------------------------------


import excel "$in_files/driving.xlsx", sheet("Sheet2") firstrow clear

drop if bac_limit == .
drop if low_age_limit == .
drop if up_age_limit == .

drop if Jurisdiction == "US( United States)"

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations


split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"
	

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before policy change"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

		
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq
		
		egen year_max = max(year_end), by(juri) // all policies last until 1/1/2017 in the end.
		
* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)

*tsset juri  year_quarter_start2  
bysort juri: gen time = _n
tsset juri time

tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .

* calculate "study quarters" - 80 for each state.
*bysort juri: gen time = _n


* obtain state abbreviations so you can merge datasets on them
gen str11 state_abr = substr(Jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start
drop time
bysort state_abr: gen time = _n

* replace missing values that happen due to data expansion above 
sort state_abr year_start quarter_start
foreach m in days  bac_limit low_age_limit up_age_limit {
bysort state_abr: replace `m' = `m'[_n-1] if `m'== . 
}

foreach l in PerSe Citations{
bysort state_abr: replace `l' = `l'[_n-1] if `l' == ""
}


* put all variables lower care
rename *, lower

* drop variables we do not need for now
drop _fillin dailydate2 dailydate1 year_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter


* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change daterange state_abr year quarter

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
	
gen no_change20032007 = (daterange == "1/1/2003 - 1/1/2017")
	label var no_change20032007 "No change in policy btw 2003 and 2017"
	
	drop if state_abr == ""
	
	drop if year ==.
	
*** replace perse = "No" if missing
replace perse = "No" if perse == ""

	saveold "$out_files/underage_vehicle_operator.dta", replace
break;;;
	
*------------------------------------------------------------------------------
*  TAXES
*------------------------------------------------------------------------------

************
*** Make datasets compatible
************

* WINE

import excel "$in_files/taxes/wine/wine.xlsx", sheet("all_states") firstrow clear

rename AdditionalTaxesfor614Alcoh AdditionalTaxesforXAlc
rename F OnAdVal_retail
rename G OnSalesT_notapply
rename H OnSalesT
rename I OnSalesT_AdjRetAdVal
rename K OffRetailTax
rename L OffSalesTax_notapply
rename M OffSalesTax
rename N OffSalesT_AdjRetAdVal

* apply additional cleanings 
/*
replace SpecificExciseTaxPerGallonf = subinstr(SpecificExciseTaxPerGallonf, "$", "", .)
destring SpecificExciseTaxPerGallonf, replace force
 
foreach l in OnAdVal_retail  OnSalesT  AdValoremExciseTaxOffPremis OffRetailTax OffSalesTax  OffSalesT_AdjRetAdVal OnSalesT_AdjRetAdVal AdValoremExciseTaxOnPremise{
replace `l' = subinstr(`l', "%", "",.)  // remove %
destring `l', replace force // make them numeric
}
*/

saveold "$out_files/wine_temporary.dta", replace

* BEER

import excel "$in_files/taxes/beer/beer.xlsx", sheet("all_states") firstrow clear

rename AdditionalTaxesfor326Alco AdditionalTaxesforXAlc
rename F OnAdVal_retail
rename G OnSalesT_notapply
rename H OnSalesT
rename I OnSalesT_AdjRetAdVal
rename K OffRetailTax
rename L OffSalesTax_notapply
rename M OffSalesTax
rename N OffSalesT_AdjRetAdVal

* apply additional cleanings 
/*
replace SpecificExciseTaxPerGallonf = subinstr(SpecificExciseTaxPerGallonf, "$", "", .)
destring SpecificExciseTaxPerGallonf, replace force
 
foreach l in OnAdVal_retail  OnSalesT  AdValoremExciseTaxOffPremis OffRetailTax OffSalesTax  OffSalesT_AdjRetAdVal OnSalesT_AdjRetAdVal AdValoremExciseTaxOnPremise{
replace `l' = subinstr(`l', "%", "",.)  // remove %
destring `l', replace force // make them numeric
}
*/

saveold "$out_files/beer_temporary.dta", replace


* SPIRITS

import excel "$in_files/taxes/spirits/spirits.xlsx", sheet("all_states") firstrow clear

rename AdditionalTaxesfor1550Alco AdditionalTaxesforXAlc
rename F OnAdVal_retail
rename G OnSalesT_notapply
rename H OnSalesT
rename I OnSalesT_AdjRetAdVal
rename K OffRetailTax
rename L OffSalesTax_notapply
rename M OffSalesTax
rename N OffSalesT_AdjRetAdVal

* apply additional cleanings 
/*
replace SpecificExciseTaxPerGallonf = subinstr(SpecificExciseTaxPerGallonf, "$", "", .)
destring SpecificExciseTaxPerGallonf, replace force
 
foreach l in OnAdVal_retail  OnSalesT  AdValoremExciseTaxOffPremis OffRetailTax OffSalesTax  OffSalesT_AdjRetAdVal OnSalesT_AdjRetAdVal AdValoremExciseTaxOnPremise{
replace `l' = subinstr(`l', "%", "",.)  // remove %
destring `l', replace force // make them numeric
}
*/

saveold "$out_files/spirits_temporary.dta", replace

************
*** Clean each dataset so that it runs from 1998q1 - 2017q4
************

foreach x in wine beer spirits {

use "$out_files/`x'_temporary.dta", replace

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations

* identify start dates of policy changes 

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"
	

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before tax change:`x'"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

		
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq
		
		egen year_max = max(year_end), by(juri) // all policies last until 1/1/2017 in the end.
		
* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)
tsset juri year_quarter_start2
tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .

* calculate "study quarters" - 80 for each state.
bysort juri: gen time = _n


* obtain state abbreviations so you can merge datasets on them
gen str11 state_abr = substr(Jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start
drop time
bysort state_abr: gen time = _n

* replace missing values that happen due to data expansion above 
sort state_abr year_start quarter_start
foreach m in days SpecificExciseTaxPerGallonf OnAdVal_retail  OnSalesT  AdValoremExciseTaxOffPremis OffRetailTax OffSalesTax  OffSalesT_AdjRetAdVal OnSalesT_AdjRetAdVal AdValoremExciseTaxOnPremise {
bysort state_abr: replace `m' = `m'[_n-1] if `m'== . 
}

bysort state_abr: replace Control = Control[_n-1] if Control == ""

foreach l in OffSalesTax_notapply OnSalesT_notapply {
bysort state_abr: replace `l' = `l'[_n-1] if `l' == ""
}

rename SpecificExciseTaxPerGallonf SpecExcGal
rename AdValoremExciseTaxOnPremis  AdValExcOnPrem
rename AdValoremExciseTaxOffPremis AdValExcOffPrem


* rename variables according to wine/beer/spirits policy change
foreach z in  SpecExcGal OnAdVal_retail AdValExcOffPrem OnSalesT OffRetailTax OffSalesTax  OffSalesT_AdjRetAdVal OnSalesT_AdjRetAdVal AdValExcOnPrem  {

	rename `z' tax`z'`x'
}

* put all variables lower care
rename *, lower

* drop variables we do not need for now
drop quart1 year1 year_quarter_start2 _fillin dailydate2 dailydate1 year_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter


* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change daterange state_abr year quarter tax*

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
	
gen no_change20032007 = (daterange == "1/1/2003 - 1/1/2017")
	label var no_change20032007 "No change in policy btw 2003 and 2017"
	
	drop if state_abr == ""
	
	merge m:1 state_abr year using "$out_files/state_sales_taxes_all.dta"
	
save "$out_files/`x'_taxes.dta", replace
	label data "Alcohol policies - taxes: `x'"
}

*** DC check again!!! --> DONE, I think fixed now. It was missing in the first data. 

*------------------------------------------------------------------------------
* UNDERAGE DRINKING
*------------------------------------------------------------------------------

import excel "$in_files/min_drink_age/min_drink_age/min_drink_age.xlsx", sheet("all_states") firstrow clear

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations

* identify start dates of policy changes 

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before tax change:`x'"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

	
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq


* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)
tsset juri year_quarter_start2
tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .
	

rename *, lower

gen str11 state_abr = substr(jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start


sort state_abr year_start quarter_start
foreach m in purchaseprohibited youthmaypurchaseforlawenfor{
bysort state_abr: replace `m' = `m'[_n-1] if `m'== "" 
			 replace `m' = "No Law" if citationscount == "No Law1 Citations" | citationscount == "No Law4 Citations" | citationscount == "No Law"
} 

rename purchaseprohibited uage_prohibited
rename youthmaypurchaseforlawenfor uage_canpurch_forlaw

* drop variables we do not need for now
drop quart1 year1 year_quarter_start2 _fillin dailydate2 dailydate1 year_end  quarter_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter


* calculate "study quarters" - 80 for each state.
bysort state_abr: gen time = _n

* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change state_abr year quarter 

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
		
* final cleaning

replace uage_canpurch_forlaw = "No Law" if uage_canpurch_forlaw == "" & policy_change == 1
replace uage_prohibited = "No Law" if uage_prohibited == "" & policy_change == 1

	
gen no_change19982017 = (daterange == "1/1/1998 - 1/1/2017")
	label var no_change19982017 "No change in policy btw 1998 and 2017"

save "$out_files/minimum_drinking_age.dta", replace

	

************
*** Sunday sales
************

import excel "$in_files/sunday_liq_sales/sunday_sales/sunday_sales.xlsx", sheet("Worksheet 1") firstrow clear

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations

* identify start dates of policy changes 

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before tax change:`x'"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

	
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq


* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)
tsset juri year_quarter_start2
tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .

gen str11 state_abr = substr(Jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start

foreach x in ExceptionsLocalOption BanRepealed Exceptions32BeerSalesAllow {
bysort state_abr: replace `x' = `x'[_n-1] if `x' == "" 
}

rename *, lower

rename daterange  daterange_sun

* calculate "study quarters" - 80 for each state.
bysort state_abr: gen time = _n

* drop variables we do not need for now
drop quart1 year1 year_quarter_start2 _fillin dailydate2 dailydate1 year_end  quarter_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter

* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change state_abr year quarter 

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
		
* final cleanups

rename banrepealed sun_banrepeal
	replace sun_banrepeal = "No" if sun_banrepeal == "" & policy_change == 1
	
			gen sun_ban = (sun_banrepeal == "No")
				label var sun_ban "Limited sale of alcohol on Sundays"
			
rename exceptionslocaloption sun_exclocaloption
	replace sun_exclocaloption = "No" if sun_exclocaloption == "" & policy_change == 1
		label var sun_exclocaloption "Sunday sale: local option"
rename exceptions32beersalesallow sun_exc32beersalesallow
	replace sun_exc32beersalesallow = "No" if sun_exc32beersalesallow == "" & policy_change == 1
	
	
	*** assume that for states that did NOT ever repeal, sun_ban == 0.
	replace sun_ban =0 if policy_change == .
	
save "$out_files/sundaysales.dta", replace
	label data "Alcohol policies for sunday sales restrictions"


************
* Blood alcohol content
************

import excel "$in_files/bac/bac/bac.xls", sheet("all_states") firstrow clear

encode Jurisdiction, gen(juri) // be careful: do not merge anything on juri - this is just for WITHIN dataset manipulations

* identify start dates of policy changes 

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"

* calculate duration of policy 

gen long days = dailydate2-dailydate1
	label var days "Policy duration before tax change:`x'"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq

	
gen quarter_end = quarter(dailydate2)
gen year_quarter_end = yq(year_end,quarter_end)
format year_quarter_end %tq


* fill in missing quarters and years 
fillin juri quarter_start year_start
sort juri year_start quarter_start
gen year_quarter_start2 = yq(year_start,quarter_start)
tsset juri year_quarter_start2
tsfill, full
format year_quarter_start2 %tq 
convdate year year1 =year_quarter_start2
sort juri year1 quarter_start
bysort juri year1: gen quart1 = _n

	replace quarter_start = quart1 if quarter_start == . 
	replace year_start = year1 if year_start == .

gen str11 state_abr = substr(Jurisdiction,1,2)
		replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	
		label var state_abr "State - abr"

* indicator on whether the state was in this file (that is, the policy changed), or not (if 0 --> not). 
gen policy_change = 1

* merge in other states and years so that we have 51 states and 1998-2017 matrix
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start


rename *, lower

rename daterange daterange_bac

* calculate "study quarters" - 80 for each state.
bysort state_abr: gen time = _n

* drop variables we do not need for now
drop quart1 year1 year_quarter_start2 _fillin dailydate2 dailydate1 year_end  quarter_end day_end month_end day_start juri jurisdiction 

* rename time variables into year and quarter
rename year_start year
rename quarter_start quarter

* sort data so that it is easier to read immediately
sort state_abr year quarter
order time policy_change state_abr year quarter 

* replace policy_change
egen last_year = max(year) if policy_change!=.
	egen last_year_st = mean(last_year), by(state_abr)
	
	replace policy_change = 1 if policy_change == . & year>last_year_st
	replace policy_change = 0 if policy_change == .
		drop last_year last_year_st
		
* final cleanups
sort state_abr year quarter
gen bac_limit = baclimit
bysort state_abr: replace bac_limit = bac_limit[_n-1] if bac_limit == . & policy_change == 1
	label var bac_limit "BAC limit"

order time policy_change state_abr year quarter bac_limit

drop baclimit

gen no_change19982017 = (daterange == "1/1/1998 - 1/1/2017")
	label var no_change19982017 "No change in policy btw 1998 and 2017"

	
save "$out_files/blood_alcohol_content.dta", replace
	label data "Alcohol policies for blood alcohol content"
	
	
	break;;;


************************** RWJF COUNTY DATA  **********************************

*------------------------------------------------------------------------------
* IMPORT DATA AND APPLY BASIC EDITS TO DATES
*------------------------------------------------------------------------------
** check what year liquor store and why. data source - why didnt they include it!


foreach x in 2010 2011 2012 2016 2017 2018 {
import excel "$in_files/`x' County Health Rankings National Data_v2.xls", sheet("short") firstrow clear

gen year = `x'

rename *, lower

keep fips state county smokers cilowsmokers cihighsmokers quartilesmokers bingedrinking ///
	 cilowbinge cihighbinge quartilebinge mvmortalityrate cilowmvmortality cihighmvmortality ///
	 quartilemvmortality year
	 
save "$out_files/rwjf_countyhealth_`x'.dta", replace
	label data "RWJF County `x' data"
}


foreach x in 2013 2014 2015 {
import excel "$in_files/`x' County Health Rankings National Data_v2.xls", sheet("short") firstrow clear

gen year = `x'

rename *, lower

keep fips state county smokers cilowsmokers cihighsmokers quartilesmokers bingedrinking ///
	 cilowbinge cihighbinge quartilebinge mvmortalityrate  ///
	 quartilemvmortality year
	 
save "$out_files/rwjf_countyhealth_`x'.dta", replace
	label data "RWJF County `x' data"
}


use "$out_files/rwjf_countyhealth_2010.dta", clear 
	append using "$out_files/rwjf_countyhealth_2011.dta", force
	append using "$out_files/rwjf_countyhealth_2012.dta", force
	append using "$out_files/rwjf_countyhealth_2013.dta", force
	append using "$out_files/rwjf_countyhealth_2014.dta", force
	append using "$out_files/rwjf_countyhealth_2015.dta", force
	append using "$out_files/rwjf_countyhealth_2016.dta", force
	append using "$out_files/rwjf_countyhealth_2017.dta", force
	append using "$out_files/rwjf_countyhealth_2018.dta", force
	
	
	
	
gen binge_year = "2002-2008" 		 if year == 2010
	replace binge_year = "2003-2009" if year == 2011
	replace binge_year = "2004-2010" if year == 2012
	replace binge_year = "2005-2011" if year == 2013
	replace binge_year = "2006-2012" if year == 2014
	replace binge_year = "2006-2012" if year == 2015 // double check 
	replace binge_year = "2014"      if year == 2016
	replace binge_year = "2015" 	 if year == 2017
	replace binge_year = "2016"  	 if year == 2018
		label var binge_year "Data source year for binge drinking"
	
gen mvmort_year = "2000-2006" 		if year == 2010
	replace mvmort_year = "2001-2007" if year == 2011
	replace mvmort_year = "2002-2008" if year == 2012
	replace mvmort_year = "2004-2010" if year == 2013
	replace mvmort_year = "2008-2012" if year == 2014
	replace mvmort_year = "2009-2013" if year == 2015
	replace mvmort_year = "2010-2014" if year == 2016
	replace mvmort_year = "2011-2015" if year == 2017
	replace mvmort_year = "2012-2016" if year == 2018
		label var mvmort_year "Data source year for MV mortality rate"
	
	
gen smokers_year = "2002-2008" 		   if year == 2010
	replace smokers_year = "2003-2009" if year == 2011
	replace smokers_year = "2004-2010" if year == 2012
	replace smokers_year = "2005-2011" if year == 2013
	replace smokers_year = "2006-2012" if year == 2014
	replace smokers_year = "2006-2012" if year == 2015 // odd because US overall changed from 2014 from 18 to 20% --> maybe email RWJF or double check!!!!!! is there a reason why single year is used later and before such a long period (are they going to fix this)
	replace smokers_year = "2014" 	   if year == 2016 // count counties
	replace smokers_year = "2015" 	   if year == 2017
	replace smokers_year = "2016" 	   if year == 2018
		label var smokers_year "Data source year for smoking"
	 
*** order data

order year *year fips state county

sort year state county

drop if state == ""

drop if county == "" // 51 obs get deleted from 2013 because it reports state average in each row for 51 states

*** save data

saveold "$out_files/rwjf_countyhealth_cleaned.dta", replace


	break;;;
	
	
******** NOT DONE PROPERLY YET ******* (as of July 22nd 2018) ******************

*------------------------------------------------------------------------------
*  RETAIL/WHOLESALE - not finished for now (from NIAA website)
*------------------------------------------------------------------------------

* discuss - how to code these variables directly.... ? Leave as is for now. Perhaps re-structure excel so that it resembles taxes. 

foreach x in wine beer spirits {

	foreach z in retail wholesales {

import excel "$in_files/`z'/`z'_`x'/`z'_`x'.xls", sheet("Worksheet 1") firstrow clear

 
 encode Jurisdiction, gen(juri)

split DateRange, p("/" "-")
destring DateRange1-DateRange6, replace force
gen dailydate1 = mdy(DateRange1, DateRange2, DateRange3)
format dailydate %d
gen dailydate2 = mdy(DateRange4, DateRange5, DateRange6)
format dailydate2 %d

rename DateRange1 month_start
	label var month_start "Month: start"
rename DateRange2 day_start
	label var day_start "Day: start"
rename DateRange3 year_start
	label var year_start "Year: start"
rename DateRange4 month_end
	label var month_end "Month: end"
rename DateRange5 day_end
	label var day_end "Day: end"
rename DateRange6 year_end
	label var year_end "Year: end"


gen long days = dailydate2-dailydate1
	label var days "Policy duration before tax change:`x'"
	
gen quarter_start = quarter(dailydate1)
gen year_quarter_start = yq(year_start,quarter_start)
format year_quarter_start %tq
 
duplicates drop juri quarter_start year_start, force

 
fillin juri quarter_start year_start
sort juri year_start quarter_start

bysort juri: gen time = _n



order time quarter_start year_start juri DateRange days 

rename *, lower


foreach m in distributionsystemoverall distributionsystemby`x' `x'subtypealcoholcontent {
bysort juri: replace `m' = `m'[_n-1] if `m'== "" 
			 replace `m' = "No Law" if citationscount == "No Law"
}
	
rename *, lower
rename citations citations`x'`z'

keep jurisdiction year_quarter_start time juri  quarter_start year_start distributionsystemoverall distributionsystemby`x' `x'subtypealcoholcontent 

rename distributionsystemoverall distrall_`z'_`x'
rename distributionsystemby`x' distrby_`z'_`x'
rename `x'subtypealcoholcontent distralcont_`z'_`x'

** clean 

gen str11 state_abr = substr(jurisdiction,1,2)
replace state_abr = state_abr[_n-1] if juri == juri[_n-1]	

/*
merge m:1 state_abr year_start quarter_start using "$out_files/states_years_1998_2016_quarters_all.dta"
drop _merge 
sort state_abr year_start quarter_start
bysort state_abr: gen time1 = _n

drop time
*/

save "$out_files/`z'_`x'.dta", replace
	label data "Alcohol policies for `z' - `x'"
	}	
}




*****************
* MERGE ALL ALCOHOL POLICIES DATA 
*****************


use "$out_files/blood_alcohol_content.dta", clear

	foreach x in sundaysales minimum_drinking_age wine_taxes beer_taxes spirits_taxes retail_wine  retail_beer retail_spirits  wholesales_wine wholesales_beer wholesales_spirits  {

	merge 1:1 quarter_start year_start state_abr using "$out_files/`x'.dta", force
	rename _merge merge_`x'
}

sort state_abr year_start quarter_start

	
foreach z in wine spirits beer {

	foreach x in taxspecexcgal`z' taxonadval_retail`z' taxonsalest`z' taxadvalexcoffprem`z' ///
			 taxoffretailtax`z' taxoffsalestax`z' taxoffsalest_adjretadval`z' taxonsalest_adjretadval`z' taxadvalexconprem`z' {
			 		 
bysort juri: replace `x' = `x'[_n-1] if `x' == .
}
}
			 		 
bysort juri: replace bac_limit= bac_limit[_n-1] if bac_limit == .	
	
foreach z in wine spirits beer {
	
	foreach x in  distrall_retail_`z' distrby_retail_`z' distralcont_retail_`z' ///
				  distrall_wholesales_`z' distrby_wholesales_`z' distralcont_wholesales_`z'  {
				  
bysort juri: replace `x' = `x'[_n-1] if `x' == ""
}
}


replace uage_prohibited = "No" if uage_prohibited == ""
replace uage_canpurch_forlaw = "No" if uage_canpurch_forlaw == ""
replace sun_banrepeal = "No" if sun_banrepeal == ""
replace sun_exclocaloption = "No" if sun_exclocaloption == ""
replace sun_exc32beersalesallow = "No" if sun_exc32beersalesallow == ""
replace sun_ban = 0 if sun_ban == .	


*** ordering variables

order time quarter_start year_start juri bac_limit uage_prohibited uage_canpurch_forlaw tax* distr*
*** final cleanup of the data

drop merge_* sun_banrepeal daterange*

*** save data 
	save "$out_files/alcohol_policies_combined.dta", replace
		label data "Alcohol policies combined"
		
	break;;; 	








