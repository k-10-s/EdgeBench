
#The pandas .convert_objects() function is deprecated
#Couldnt get the new function to work properly, didnt want to waste more time on it
import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)
import matplotlib.pyplot as plt
import pandas as pd
from scipy import stats
from scipy.stats import norm
import numpy as np
import seaborn as sns
import statsmodels.api as sm
from statsmodels.formula.api import ols
import statsmodels.stats.multicomp
import probscale
import sys

#ANOVA
#Thanks to Marvin for Python help

if len(sys.argv) <= 5:
	print("Not enough args usage: anova.py <*.csv> <rv> <factors> <replicates> <alpha> optional: device")
	print("ex: anova.py testdata.csv nicdrop 5 10 .05 TX1")
	print("<rv> is response variable")
	print("\"Device\" is used in normplot of effects, omit to skip graph")
	exit()

n = int(sys.argv[4]) #replicates
k = int(sys.argv[3]) #factors
alpha = float(sys.argv[5])
rv = str(sys.argv[2])


if k > 5 or k < 1:
	print("Max factors is 5, Min is 1")
	exit()


data2 = pd.read_csv(sys.argv[1], header=[0,1])
response_var = data2[[rv,'factors']]
response_var.columns = response_var.columns.get_level_values(1)
#print(response_var.groupby('code').mean().sort_values(by=['avg']).round(0))

if(k >= 1):
	df_index=['A', 'Error', 'Total']
	one = response_var[response_var['code'] == 'N'].loc[:,'avg'].to_numpy()
	a 	= response_var[response_var['code'] == 'A'].loc[:,'avg'].to_numpy()
	means_all = np.array([np.mean(a)])
	total = np.array([one, a])
	contrast_A = np.sum(-one + a)
	contrasts_all = np.array([contrast_A])
if(k >= 2):
	df_index=['A', 'B', 'AB', 'Error', 'Total']
	one = response_var[response_var['code'] == 'N'].loc[:,'avg'].to_numpy()
	a 	= response_var[response_var['code'] == 'A'].loc[:,'avg'].to_numpy()
	b 	= response_var[response_var['code'] == 'B'].loc[:,'avg'].to_numpy()
	ab 	= response_var[response_var['code'] == 'AB'].loc[:,'avg'].to_numpy()
	means_all = np.array([np.mean(a), np.mean(b), np.mean(ab)])
	total = np.array([one, a, b, ab])
	contrast_A = np.sum(-one + a - b + ab)
	contrast_B = np.sum(-one - a + b + ab)
	contrast_AB = np.sum(one - a - b + ab)
	contrasts_all = np.array([contrast_A, contrast_B, contrast_AB])
if(k >= 3):
	df_index=['A', 'B', 'AB', 'C', 'AC', 'BC', 'ABC', 'Error', 'Total']
	c 	= response_var[response_var['code'] == 'C'].loc[:,'avg'].to_numpy()
	ac 	= response_var[response_var['code'] == 'AC'].loc[:,'avg'].to_numpy()
	bc 	= response_var[response_var['code'] == 'BC'].loc[:,'avg'].to_numpy()
	abc = response_var[response_var['code'] == 'ABC'].loc[:,'avg'].to_numpy()
	means_all = np.array([np.mean(a), np.mean(b), np.mean(ab), np.mean(c), np.mean(ac), np.mean(bc), np.mean(abc)])
	total = np.array([one, a, b, ab, c, ac, bc, abc])
	contrast_A = np.sum(-one + a - b + ab - c + ac - bc + abc)
	contrast_B = np.sum(-one - a + b + ab - c - ac + bc + abc)
	contrast_AB = np.sum(one - a - b + ab + c - ac - bc + abc)
	contrast_C = np.sum(-one - a - b - ab + c + ac + bc + abc)
	contrast_AC = np.sum(one - a + b - ab - c + ac - bc + abc)
	contrast_BC = np.sum(one + a - b - ab - c - ac + bc + abc)
	contrast_ABC= np.sum(-one+ a + b - ab + c - ac - bc + abc)
	contrasts_all = np.array([contrast_A, contrast_B, contrast_AB, contrast_C, contrast_AC, contrast_BC, contrast_ABC])
if(k >= 4):
	df_index=['A', 'B', 'AB', 'C', 'AC', 'BC', 'ABC', 'D', 'AD', 'BD', 'ABD', 'CD', 'ACD', 'BCD', 'ABCD', 'Error', 'Total']
	d 	= response_var[response_var['code'] == 'D'].loc[:,'avg'].to_numpy()
	ad 	= response_var[response_var['code'] == 'AD'].loc[:,'avg'].to_numpy()
	bd 	= response_var[response_var['code'] == 'BD'].loc[:,'avg'].to_numpy()
	abd = response_var[response_var['code'] == 'ABD'].loc[:,'avg'].to_numpy()
	cd 	= response_var[response_var['code'] == 'CD'].loc[:,'avg'].to_numpy()
	acd = response_var[response_var['code'] == 'ACD'].loc[:,'avg'].to_numpy()
	bcd = response_var[response_var['code'] == 'BCD'].loc[:,'avg'].to_numpy()
	abcd = response_var[response_var['code'] == 'ABCD'].loc[:,'avg'].to_numpy()
	means_all = np.array([np.mean(a), np.mean(b), np.mean(ab), np.mean(c), np.mean(ac), np.mean(bc), np.mean(abc), np.mean(d),
							np.mean(ad), np.mean(bd), np.mean(abd), np.mean(cd), np.mean(acd), np.mean(bcd), np.mean(abcd)])
	total = np.array([one, a, b, ab, c, ac, bc, abc, d, ad, bd, abd, cd, acd, bcd, abcd])
	contrast_A = np.sum(-one + a - b + ab - c + ac - bc + abc - d + ad - bd + abd - cd + acd - bcd + abcd)
	contrast_B = np.sum(-one - a + b + ab - c - ac + bc + abc - d - ad + bd + abd - cd - acd + bcd + abcd)
	contrast_AB = np.sum(one - a - b + ab + c - ac - bc + abc + d - ad - bd + abd + cd - acd - bcd + abcd)
	contrast_C = np.sum(-one - a - b - ab + c + ac + bc + abc - d - ad - bd - abd + cd + acd + bcd + abcd)
	contrast_AC = np.sum(one - a + b - ab - c + ac - bc + abc + d - ad + bd - abd - cd + acd - bcd + abcd)
	contrast_BC = np.sum(one + a - b - ab - c - ac + bc + abc + d + ad - bd - abd - cd - acd + bcd + abcd)
	contrast_ABC= np.sum(-one+ a + b - ab + c - ac - bc + abc - d + ad + bd - abd + cd - acd - bcd + abcd)
	contrast_D =  np.sum(-one- a - b - ab - c - ac - bc - abc + d + ad + bd + abd + cd + acd + bcd + abcd)
	contrast_AD=  np.sum(one - a + b - ab + c - ac + bc - abc - d + ad - bd + abd - cd + acd - bcd + abcd)
	contrast_BD = np.sum(one + a - b - ab + c + ac - bc - abc - d - ad + bd + abd - cd - acd + bcd + abcd)
	contrast_ABD= np.sum(-one + a + b - ab - c + ac + bc - abc + d - ad - bd + abd + cd - acd - bcd + abcd)
	contrast_CD = np.sum(one + a + b + ab - c - ac - bc - abc - d - ad - bd - abd + cd + acd + bcd + abcd)
	contrast_ACD = np.sum(-one + a - b + ab + c - ac + bc - abc + d - ad + bd - abd - cd + acd - bcd + abcd)
	contrast_BCD = np.sum(-one - a + b + ab + c + ac - bc - abc + d + ad - bd - abd - cd - acd + bcd + abcd)
	contrast_ABCD = np.sum(one - a - b + ab - c + ac + bc - abc - d + ad + bd - abd + cd - acd - bcd + abcd)
	contrasts_all = np.array([contrast_A, contrast_B, contrast_AB, contrast_C, contrast_AC, contrast_BC, contrast_ABC,
                         contrast_D, contrast_AD, contrast_BD, contrast_ABD, contrast_CD, contrast_ACD, contrast_BCD, contrast_ABCD])
if(k >= 5):
	df_index=['A', 'B', 'AB', 'C', 'AC', 'BC', 'ABC', 'D', 'AD', 'BD', 'ABD', 'CD', 'ACD', 'BCD', 'ABCD', 'E', 'AE', 'BE', 'ABE',
	'CE', 'ACE', 'BCE', 'ABCE','DE', 'ADE', 'BDE', 'ABDE', 'CDE', 'ACDE', 'BCDE', 'ABCDE', 'Error', 'Total']
	e 	= response_var[response_var['code'] == 'E'].loc[:,'avg'].to_numpy()
	ae 	= response_var[response_var['code'] == 'AE'].loc[:,'avg'].to_numpy()
	be 	= response_var[response_var['code'] == 'BE'].loc[:,'avg'].to_numpy()
	abe = response_var[response_var['code'] == 'ABE'].loc[:,'avg'].to_numpy()
	ce 	= response_var[response_var['code'] == 'CE'].loc[:,'avg'].to_numpy()
	ace = response_var[response_var['code'] ==  'ACE'].loc[:,'avg'].to_numpy()
	bce = response_var[response_var['code'] == 'BCE'].loc[:,'avg'].to_numpy()
	abce = response_var[response_var['code'] == 'ABCE'].loc[:,'avg'].to_numpy()
	de 	= response_var[response_var['code'] == 'DE'].loc[:,'avg'].to_numpy()
	ade = response_var[response_var['code'] == 'ADE'].loc[:,'avg'].to_numpy()
	bde = response_var[response_var['code'] == 'BDE'].loc[:,'avg'].to_numpy()
	abde = response_var[response_var['code'] == 'ABDE'].loc[:,'avg'].to_numpy()
	cde = response_var[response_var['code'] == 'CDE'].loc[:,'avg'].to_numpy()
	acde = response_var[response_var['code'] == 'ACDE'].loc[:,'avg'].to_numpy()
	bcde = response_var[response_var['code'] == 'BCDE'].loc[:,'avg'].to_numpy()
	abcde = response_var[response_var['code'] == 'ABCDE'].loc[:,'avg'].to_numpy()
	means_all = np.array([np.mean(a), np.mean(b), np.mean(ab), np.mean(c), np.mean(ac), np.mean(bc), np.mean(abc), np.mean(d),
							np.mean(ad), np.mean(bd), np.mean(abd), np.mean(cd), np.mean(acd), np.mean(bcd), np.mean(abcd),np.mean(e),
							np.mean(ae),np.mean(be),np.mean(abe),np.mean(ce),np.mean(ace),np.mean(bce),np.mean(abce),np.mean(de),np.mean(ade),
							np.mean(bde),np.mean(abde),np.mean(cde),np.mean(acde),np.mean(bcde),np.mean(abcde)])
	total = np.array([one, a, b, ab, c, ac, bc, abc, d, ad, bd, abd, cd, acd, bcd, abcd,
					e,ae,be,abe,ce,ace,bce,abce,de,ade,bde,abde,cde,acde,bcde,abcde])
	contrast_A = np.sum(-one + a  - b  + ab  - c  + ac  - bc  + abc  - d  + ad  - bd  + abd  - cd  + acd  - bcd  + abcd
						- e  + ae - be + abe - ce + ace - bce + abce - de + ade - bde + abde - cde + acde - bcde + abcde)
	contrast_B = np.sum(-one - a  + b  + ab  - c  - ac  + bc  + abc  - d  - ad  + bd  + abd  - cd  - acd  + bcd  + abcd
						- e  - ae + be + abe - ce - ace + bce + abce - de - ade + bde + abde - cde - acde + bcde + abcde)
	contrast_AB = np.sum(one - a  - b  + ab  + c  - ac  - bc  + abc  + d  - ad  - bd  + abd  + cd  - acd  - bcd  + abcd
						+ e  - ae - be + abe + ce - ace - bce + abce + de - ade - bde + abde + cde - acde - bcde + abcde)
	contrast_C = np.sum(-one - a  - b  - ab  + c  + ac  + bc  + abc  - d  - ad  - bd  - abd  + cd  + acd  + bcd  + abcd
						- e  - ae - be - abe + ce + ace + bce + abce - de - ade - bde - abde + cde + acde + bcde + abcde)
	contrast_AC = np.sum(one - a  + b  - ab  - c  + ac  - bc  + abc  + d  - ad  + bd  - abd  - cd  + acd  - bcd  + abcd
						+ e  - ae + be - abe - ce + ace - bce + abce + de - ade + bde - abde - cde + acde - bcde + abcde)
	contrast_BC = np.sum(one + a  - b  - ab  - c  - ac  + bc  + abc  + d  + ad  - bd  - abd  - cd  - acd  + bcd  + abcd
						+ e  + ae - be - abe - ce - ace + bce + abce + de + ade - bde - abde - cde - acde + bcde + abcde)
	contrast_ABC= np.sum(-one + a  + b  - ab  + c  - ac  - bc  + abc  - d  + ad  + bd  - abd  + cd  - acd  - bcd  + abcd
						 - e  + ae + be - abe + ce - ace - bce + abce - de + ade + bde - abde + cde - acde - bcde + abcde)
	contrast_D =  np.sum(-one - a  - b  - ab  - c  - ac  - bc  - abc  + d  + ad  + bd  + abd  + cd  + acd  + bcd  + abcd
						 - e  - ae - be - abe - ce - ace - bce - abce + de + ade + bde + abde + cde + acde + bcde + abcde)
	contrast_AD=  np.sum(one - a  + b  - ab  + c  - ac  + bc  - abc  - d  + ad  - bd  + abd  - cd  + acd  - bcd  + abcd
						+ e  - ae + be - abe + ce - ace + bce - abce - de + ade - bde + abde - cde + acde - bcde + abcde)
	contrast_BD = np.sum(one + a  - b  - ab  + c  + ac  - bc  - abc  - d  - ad  + bd  + abd  - cd  - acd  + bcd  + abcd
						+ e  + ae - be - abe + ce + ace - bce - abce - de - ade + bde + abde - cde - acde + bcde + abcde)
	contrast_ABD= np.sum(-one + a + b  - ab  - c  + ac  + bc  - abc  + d  - ad  - bd  + abd  + cd  - acd  - bcd  + abcd
						 - e + ae + be - abe - ce + ace + bce - abce + de - ade - bde + abde + cde - acde - bcde + abcde)
	contrast_CD = np.sum(one + a  + b  + ab  - c  - ac  - bc  - abc  - d  - ad  - bd  - abd  + cd  + acd  + bcd  + abcd
						+ e  + ae + be + abe - ce - ace - bce - abce - de - ade - bde - abde + cde + acde + bcde + abcde)
	contrast_ACD = np.sum(-one + a  - b  + ab  + c  - ac  + bc  - abc  + d  - ad  + bd  - abd  - cd  + acd  - bcd  + abcd
						  - e  + ae - be + abe + ce - ace + bce - abce + de - ade + bde - abde - cde + acde - bcde + abcde)
	contrast_BCD = np.sum(-one - a  + b  + ab  + c  + ac  - bc  - abc  + d  + ad  - bd  - abd  - cd  - acd  + bcd  + abcd
						  - e  - ae + be + abe + ce + ace - bce - abce + de + ade - bde - abde - cde - acde + bcde + abcde)
	contrast_ABCD = np.sum(one - a  - b  + ab  - c  + ac  + bc  - abc  - d  + ad  + bd  - abd  + cd  - acd  - bcd  + abcd
						  + e  - ae - be + abe - ce + ace + bce - abce - de + ade + bde - abde + cde - acde - bcde + abcde)
	contrast_E = np.sum(-one - a  - b  - ab  - c  - ac  - bc  - abc  - d  - ad  - bd  - abd  - cd  - acd  - bcd  - abcd
						+ e  + ae + be + abe + ce + ace + bce + abce + de + ade + bde + abde + cde + acde + bcde + abcde)
	contrast_AE = np.sum(one - a  + b  - ab  + c  - ac  + bc  - abc  + d  - ad  + bd  - abd  + cd  - acd  + bcd  - abcd
					    - e  + ae - be + abe - ce + ace - bce + abce - de + ade - bde + abde - cde + acde - bcde + abcde)
	contrast_BE= np.sum(one + a  - b  - ab  + c  + ac  - bc  - abc  + d  + ad  - bd  - abd  + cd  + acd  - bcd  - abcd
						- e - ae + be + abe - ce - ace + bce + abce - de - ade + bde + abde - cde - acde + bcde + abcde)
	contrast_ABE= np.sum(-one + a  + b  - ab  - c  + ac  + bc  - abc  - d  + ad  + bd  - abd  - cd  + acd  + bcd  - abcd
						 + e  - ae - be + abe + ce - ace - bce + abce + de - ade - bde + abde + cde - acde - bcde + abcde)
	contrast_CE= np.sum(one + a  + b  + ab  - c  - ac  - bc  - abc  + d  + ad  + bd  + abd  - cd  - acd  - bcd  - abcd
						- e - ae - be - abe + ce + ace + bce + abce - de - ade - bde - abde + cde + acde + bcde + abcde)
	contrast_ACE= np.sum(-one + a  - b  + ab  + c  - ac  + bc  - abc  - d  + ad  - bd  + abd  + cd  - acd  + bcd  - abcd
						 + e  - ae + be - abe - ce + ace - bce + abce + de - ade + bde - abde - cde + acde - bcde + abcde)
	contrast_BCE= np.sum(-one - a  + b  + ab  + c  + ac  - bc  - abc  - d  - ad  + bd  + abd  + cd  + acd  - bcd  - abcd
					  	 + e  + ae - be - abe - ce - ace + bce + abce + de + ade - bde - abde - cde - acde + bcde + abcde)
	contrast_ABCE= np.sum(one - a  - b  + ab  - c  + ac  + bc  - abc  + d  - ad  - bd  + abd  - cd  + acd  + bcd  - abcd
						  - e + ae + be - abe + ce - ace - bce + abce - de + ade + bde - abde + cde - acde - bcde + abcde)
	contrast_DE= np.sum(one + a  + b  + ab  + c  + ac  + bc  + abc  - d  - ad  - bd  - abd  - cd  - acd  - bcd  - abcd
						- e - ae - be - abe - ce - ace - bce - abce + de + ade + bde + abde + cde + acde + bcde + abcde)
	contrast_ADE= np.sum(-one + a  - b  + ab  - c  + ac  - bc  + abc  + d  - ad  + bd  - abd  + cd  - acd  + bcd  - abcd
						 + e  - ae + be - abe + ce - ace + bce - abce - de + ade - bde + abde - cde + acde - bcde + abcde)
	contrast_BDE= np.sum(-one - a  + b  + ab  - c  - ac  + bc  + abc  + d  + ad  - bd  - abd  + cd  + acd  - bcd  - abcd
						 + e  + ae - be - abe + ce + ace - bce - abce - de - ade + bde + abde - cde - acde + bcde + abcde)
	contrast_ABDE= np.sum(one - a  - b  + ab  + c  - ac  - bc  + abc  - d  + ad  + bd  - abd  - cd  + acd  + bcd  - abcd
						 - e  + ae + be - abe - ce + ace + bce - abce + de - ade - bde + abde + cde - acde - bcde + abcde)
	contrast_CDE= np.sum(-one - a  - b  - ab  + c  + ac  + bc  + abc  + d  + ad  + bd  + abd  - cd  - acd  - bcd  - abcd
						 + e  + ae + be + abe - ce - ace - bce - abce - de - ade - bde - abde + cde + acde + bcde + abcde)
	contrast_ACDE= np.sum(one - a  + b  - ab  - c  + ac  - bc  + abc  - d  + ad  - bd  + abd  + cd  - acd  + bcd  - abcd
						 - e  + ae - be + abe + ce - ace + bce - abce + de - ade + bde - abde - cde + acde - bcde + abcde)
	contrast_BCDE= np.sum(one + a  - b  - ab  - c  - ac  + bc  + abc  - d  - ad  + bd  + abd  + cd  + acd  - bcd  - abcd
						  - e - ae + be + abe + ce + ace - bce - abce + de + ade - bde - abde - cde - acde + bcde + abcde)
	contrast_ABCDE= np.sum(-one + a  + b  - ab  + c  - ac  - bc  + abc  + d  - ad  - bd  + abd  - cd  + acd  + bcd  - abcd
						   + e  - ae - be + abe - ce + ace + bce - abce - de + ade + bde - abde + cde - acde - bcde + abcde)

	contrasts_all = np.array([contrast_A, contrast_B, contrast_AB, contrast_C, contrast_AC, contrast_BC, contrast_ABC,
							 contrast_D, contrast_AD, contrast_BD, contrast_ABD, contrast_CD, contrast_ACD, contrast_BCD, contrast_ABCD,
							 contrast_E, contrast_AE, contrast_BE, contrast_ABE, contrast_CE, contrast_ACE, contrast_BCE, contrast_ABCE,
							 contrast_DE, contrast_ADE, contrast_BDE, contrast_ABDE, contrast_CDE, contrast_ACDE, contrast_BCDE, contrast_ABCDE])


# Sum Squares
num_effects = np.power(2,k)-1
num_elements = num_effects+2
sum_squares = np.ones(num_elements) #All effects plus error and total
for i in range(num_effects):
    sum_squares[i] = np.square(contrasts_all[i])/(n*np.power(2,k))
total_mean = np.mean(total)
SST = np.sum(np.square(total - total_mean))
SSE = SST - np.sum(sum_squares[0:num_effects])
sum_squares[num_effects] = SSE
sum_squares[num_effects+1] = SST

#Degrees of Freedom
DF = np.ones(num_elements)
DF[num_effects] = np.power(2,k)*(n-1) # Error DoF
DF[num_effects+1] = n*np.power(2,k)-1 # Total DoF

#Mean Squares
mean_squares = np.ones(sum_squares.size)
for i in range(num_elements):
    mean_squares[i] = sum_squares[i]/DF[i]
MSE = mean_squares[num_effects]

#F-values
f_vals = np.ones(num_elements)
f_vals[num_effects:] = 0
f_crits = np.ones(num_elements)
f_crits[num_effects:] = 0

#P-values
p_vals = np.ones(num_elements)
p_vals[num_effects:] = 0

#Effect Estimates
effects = np.ones(num_elements)
effects[num_effects:] = 0

#Response variable averages
means = np.ones(num_elements)
means[num_effects:] = 0

#Build datafile
for i in range(num_effects):
    F0 = mean_squares[i]/MSE
    f_vals[i] = F0
    f_crits[i] = stats.f.ppf(1-alpha,DF[i],DF[num_effects])
    p_vals[i] = 1 - stats.f.cdf(F0, DF[i],DF[num_effects])
    effects[i] = contrasts_all[i]/(n*np.power(2,k-1))
    means[i] = means_all[i]

anova_df_numpy = np.array([means, effects, sum_squares, DF, mean_squares, f_vals, f_crits, p_vals])
anova_df_pandas = pd.DataFrame(data=anova_df_numpy.T, index=df_index, columns=['Sample Mean','Effect Est.','Sum of Squares', 'df', 'Mean Square', 'F0', 'F Threshold', 'p-value'])
anova_df_pandas = anova_df_pandas.replace(to_replace=0,value='')

#The deprecated function. Changes p-value to float64 so it can be rounded properly
anova_df_pandas['p-value']= anova_df_pandas['p-value'].convert_objects(convert_numeric=True)
print("Unoptimized Mean: " + str(np.mean(one)))
print(anova_df_pandas.round(5))

##Significant Factors Only
significant_factors = anova_df_pandas[(anova_df_pandas['p-value'] < alpha)].round(5)
candidiate_factors = significant_factors[(significant_factors['Effect Est.'] < 0)].sort_values(by=['Sample Mean'])
longest = ""

if candidiate_factors.empty == False:
	print("\nSignificant Factors (alpha = " + str(alpha) + ")")
	#Only want negative (good) effects
	print(significant_factors[(significant_factors['Effect Est.'] < 0)].sort_values(by=['Sample Mean']))
	#It better be less then the unoptimized mean...
	candidiate_factors_index = candidiate_factors[(candidiate_factors['Sample Mean'] < np.mean(one))].sort_values(by=['Sample Mean']).index.array

	for x in candidiate_factors_index:
		if len(x) > len(longest):
			longest = x

	print("\n!!--Statistically Significant Effects--!! ")
	all = ""
	for y in candidiate_factors_index:
		all = all + y + ","
	print("Lowest observed mean (target to beat)")
	print(int(significant_factors['Sample Mean'].min()))
	print("Effects")

else:
	print("\n ***No statistically significant effects with sample mean < unoptimized mean***\n")
	candidiate_factors_index = anova_df_pandas[(anova_df_pandas['Sample Mean'] < np.mean(one))].sort_values(by=['Sample Mean']).index.array

	all = ""
	for y in candidiate_factors_index:
		all = all + y + ","

	if len(all) == 0:
	
		print("Unoptimized Mean")
		print(str(np.mean(one)))
		print("All the factors made it worse")
		print("NONE")
		exit()

	#Take the factor combo with the best sample mean and keep trying
	print("Lowest observed sample mean (target to beat)")
	print(int(anova_df_pandas[(anova_df_pandas['Sample Mean'] < np.mean(one))]['Sample Mean'].min()))
	print("Next best guesses")

print(all.rstrip(','))

#Normplot of effects
if len(sys.argv) == 7:
	fig = plt.figure(figsize=(6,4))
	probscale.probplot(effects,plottype='prob',probax='y',problabel='Standard Normal Probabilities',bestfit=True)
	plt.xlabel("Normal Probability Plot of Effect Estimates")
	plt.title("Avg Packets Dropped, 30sec [" + sys.argv[6] +"]")
	plt.tight_layout()
	plt.show()
