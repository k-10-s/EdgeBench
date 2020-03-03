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

if len(sys.argv) <= 3:
	print("Not enough args usage: histogram.py *.csv <rv1,rv2> device #bins")
	exit()

rv = sys.argv[2].split(',')
input_csv_parse = sys.argv[1].split('-')

#Histogram 1
data = pd.read_csv(sys.argv[1], header=[0,1])
histogram_data_filtered = data[rv[0],rv[1]].to_numpy()

plt.subplot(1,2,1)
num_bins = int(sys.argv[4])
mu = np.mean(histogram_data_filtered) #mean
sigma = np.std(histogram_data_filtered) #stddev
n, bins, patches = plt.hist(histogram_data_filtered, num_bins, density=.9, facecolor='blue')
# add a 'best fit' line
y = norm.pdf(bins, mu, sigma)
plt.plot(bins, y, 'r--')
plt.title(rv[0] + "," + rv[1] + "[" + sys.argv[3] +"]")
plt.xlabel("")
plt.ylabel("Frequency")

plt.subplot(1,2,2)
stats.probplot(histogram_data_filtered, dist="norm", plot=plt)
plt.title("Normal Q-Q plot")
plt.tight_layout()
#plt.savefig("results/anova/"+sys.argv[3]+"-"+rv[0]+"-"+rv[1]+"-histogram-"+sys.argv[1][-8:-4]+".png")
plt.savefig("results/anova/"+sys.argv[3]+"-"+input_csv_parse[2]+"-"+rv[0]+"-"+rv[1]+"-historgram.png")