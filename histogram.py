import matplotlib.pyplot as plt
import pandas as pd
from scipy import stats
from scipy.stats import norm
import numpy as np
#import researchpy as rp
import seaborn as sns
import statsmodels.api as sm
from statsmodels.formula.api import ols
import statsmodels.stats.multicomp
import probscale
import sys

if len(sys.argv) <= 2: 
	print("Not enough args usage: histogram.py *.csv device")
	exit() 

#Histogram 1
data = pd.read_csv(sys.argv[1], header=[0,1])
histogram_data_filtered = data['nicdrop','avg'].to_numpy()

plt.subplot(1,2,1)
num_bins = 15
mu = np.mean(histogram_data_filtered) #mean 
sigma = np.std(histogram_data_filtered) #stddev
n, bins, patches = plt.hist(histogram_data_filtered, num_bins, density=1, facecolor='blue')
# add a 'best fit' line
y = norm.pdf(bins, mu, sigma)
plt.plot(bins, y, 'r--')
plt.title("Avg Packets Dropped, 30sec [" + sys.argv[2] +"]")
plt.xlabel("Packets")
plt.ylabel("Frequency")

plt.subplot(1,2,2)
stats.probplot(histogram_data_filtered, dist="norm", plot=plt)
plt.title("Normal Q-Q plot")



plt.tight_layout()
plt.show()