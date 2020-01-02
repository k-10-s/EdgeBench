import pandas as pd
import numpy as np
import sys

#Best Mean Test
if len(sys.argv) <= 3:
	print("Not enough args usage: anova.py <*.csv> <rv> <target to beat>")
	print("ex: best-mean.py testdata.csv nicdrop 95000")
	print("<rv> is response variable")
	exit()

target_to_beat = int(sys.argv[3]) #factors
rv = str(sys.argv[2])

data = pd.read_csv(sys.argv[1], header=[0,1])
response_var = data[[rv,'factors']]
response_var.columns = response_var.columns.get_level_values(1)

print("Re-run factor means")
print(response_var.groupby('code')['avg'].mean())

print("Lowest observed sample mean (target to beat)")
print(response_var.groupby('code')['avg'].mean().min())

#print factors still remaining as viable
candidiate_factors_index = response_var.groupby('code')['avg'].mean().index.array.to_numpy() #all factors from csv
improved_factors_bools = (response_var.groupby('code')['avg'].mean() < target_to_beat).to_numpy() #boolean series
all = ""
i=0
for y in candidiate_factors_index:
	if improved_factors_bools[i]:
		all = all + y + ","
	i=i+1
print("Effects")
if len(all) == 0:
	print("NONE")
	exit()
print(all.rstrip(','))
