# -*- coding: utf-8 -*-
"""
Created on Thu Apr  3 14:33:32 2025

@author: CedricCannard
"""
# 
# To balance rigor and randomness: 
#     Define a soft range, say 50–70 crash trials, and generate multiple sequences that obey this constraint.
#     Use a qRNG to pick from among these sequences, ensuring no human bias in selection.
#     Shuffle each sequence (without replacement) to maintain a random order.
#     Keep participants blind to condition frequencies and avoid providing feedback.
# 
# This way, you get:
#     No extreme trial imbalance
#     Enough randomness to prevent anticipatory strategies

# All This ensures there’s:
#    - No deterministic pattern
#    - No feedback channel via code structure
#    - Random trial order per participant

# To manage subscriptions: 
# https://quantumnumbers.anu.edu.au/pricing
# https://aws.amazon.com/marketplace/procurement?productId=7deee54b-f2b9-4a20-9818-cde75521f3f3&offerId=7gee433nc4oy904ysipuptfcj
    
# API Key
import os
main_path = r'C:\Users\CedricCannard\Documents\Python'
os.chdir(main_path)
from dotenv import load_dotenv
load_dotenv()
print("Loaded key:", os.getenv("QRANDOM_API_KEY"))  # Should print your key

# test
import qrandom
# qrandom.random()

# %%  Generate 100 sequences of qRNG random 1 and 2, 120 trials, no control over number of trials
# Repeat 100 times and assess distribution

# Each fill(1) fetches 1024 quantum numbers. So:
qrandom.fill(12)

# Then pull your sequences from that buffer — all will be quantum-generated with minimal overhead.
# Quantum numbers used: 12,000
# Requests made: 12
# Total cost: $0.60

import matplotlib.pyplot as plt
from tqdm import tqdm  # progress bar

# Parameters
n_trials = 120
n_runs = 100  # sequences to simulate

# Estimate needed batches and prefetch
required_numbers = n_runs * n_trials
batches_needed = (required_numbers + 1023) // 1024  # round up
qrandom.fill(batches_needed)

# Track counts
counts_1 = []
counts_2 = []

sequences = []
for _ in tqdm(range(n_runs), desc="Simulating sequences"):
    seq = qrandom.choices([1, 2], k=n_trials)
    sequences.append(seq)  # <- store it
    count1 = seq.count(1)
    counts_1.append(count1)
    counts_2.append(n_trials - count1)

# Plot
bins = range(min(counts_1 + counts_2), max(counts_1 + counts_2) + 2)
plt.hist(counts_1, bins=bins, alpha=0.6, label="# of 1s", color='skyblue', edgecolor='black')
plt.hist(counts_2, bins=bins, alpha=0.6, label="# of 2s", color='lightcoral', edgecolor='black')
plt.title("Distribution of # of 1s and 2s in 100 Quantum-Random Sequences")
plt.xlabel("Count in 120-trial sequence")
plt.ylabel("Frequency")
plt.legend()
plt.grid(axis='y', linestyle='--', alpha=0.6)
plt.show()

# %% Export in csv files

import csv
import os

# Create output folder if needed
output_dir = "quantum_sequences"
os.makedirs(output_dir, exist_ok=True)

# Save each sequence to a separate CSV file
for i, seq in enumerate(sequences):
    subject_id = f"sub-{i+1:03d}"
    filename = f"{subject_id}_random.csv"
    filepath = os.path.join(output_dir, filename)
    with open(filepath, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(seq)


# %% Run diagnostics

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from statsmodels.sandbox.stats.runs import runstest_1samp
from statsmodels.tsa.stattools import acf
from scipy.stats import entropy, chisquare

# --- Initialize lists for diagnostics ---
runstest_ps = []
acf_matrix = []
proportions_1 = []
shannon_entropies = []

# --- Compute diagnostics per sequence ---
for seq in sequences:
    arr = np.array(seq)

    # Wald–Wolfowitz runs test (non-parametric test to assess the randomness of
    # the binary sequences to see if there is evidence of non-random clustering 
    # or excessive streaks)
    _, p = runstest_1samp(arr, correction=True)
    runstest_ps.append(p)

    # Autocorrelation (lags 1–10)
    acf_vals = acf(arr, fft=False, nlags=10)
    acf_matrix.append(acf_vals[1:])  # exclude lag 0

    # Proportion of 1s
    p1 = np.mean(arr == 1)
    proportions_1.append(p1)

    # Shannon entropy (measures unpredictability; max = 1 for binary 0.5/0.5)
    p2 = 1 - p1
    shannon_entropies.append(entropy([p1, p2], base=2))

# Global test: chi-square for total count of 1s vs 2s
total_1 = sum(np.sum(np.array(seq) == 1) for seq in sequences)
total_2 = len(sequences[0]) * len(sequences) - total_1
chi2_stat, p_chi2 = chisquare([total_1, total_2])

# Save all metrics to CSV
acf_matrix = np.array(acf_matrix)
proportions_2 = [1 - p for p in proportions_1]

df_summary = pd.DataFrame({
    'Subject': [f"sub-{i+1:03d}" for i in range(len(sequences))],
    'Proportion_1s': proportions_1,
    'Proportion_2s': proportions_2,
    'Shannon_Entropy': shannon_entropies,
    'RunsTest_p': runstest_ps
})
acf_df = pd.DataFrame(acf_matrix, columns=[f'ACF_Lag{i+1}' for i in range(acf_matrix.shape[1])])
df_summary = pd.concat([df_summary, acf_df], axis=1)
df_summary.to_csv("qrandom_diagnostics_summary.csv", index=False)

# Print high-level results
print(f"Chi-squared test: χ² = {chi2_stat:.2f}, p = {p_chi2:.4f}")
print(f"Entropy: mean = {np.mean(shannon_entropies):.4f}, SD = {np.std(shannon_entropies):.4f}")
print("✅ Subject-level diagnostics saved to 'qrandom_diagnostics_summary.csv'")

# --- Visualization Section ---

# 1. Proportions histogram
plt.figure(figsize=(10, 4))
plt.hist(proportions_1, bins=15, color='skyblue', edgecolor='black', alpha=0.7, label='1s')
plt.hist(proportions_2, bins=15, color='lightcoral', edgecolor='black', alpha=0.7, label='2s')
plt.title('Proportion of 1s and 2s per Subject')
plt.xlabel('Proportion')
plt.ylabel('Frequency')
plt.legend()
plt.grid(axis='y', linestyle='--', alpha=0.6)
plt.tight_layout()
plt.show()

# 2. ACF boxplot
plt.figure(figsize=(10, 4))
sns.boxplot(data=acf_matrix)
plt.title('Autocorrelation per Lag (1–10)')
plt.xlabel('Lag')
plt.ylabel('Autocorrelation')
plt.tight_layout()
plt.show()

# 3. Runs test p-values
plt.figure(figsize=(6, 4))
plt.hist(runstest_ps, bins=20, color='gray', edgecolor='black')
plt.axvline(x=0.05, color='red', linestyle='--', label='p = 0.05 threshold')
plt.title('Runs Test p-values across Subjects')
plt.xlabel('p-value')
plt.ylabel('Frequency')
plt.legend()
plt.tight_layout()
plt.show()

# 4. Total count bar chart
plt.figure(figsize=(4, 4))
plt.bar(['1s', '2s'], [total_1, total_2], color=['skyblue', 'lightcoral'], edgecolor='black')
plt.title('Total Trial Counts Across All Subjects')
plt.ylabel('Count')
plt.tight_layout()
plt.show()

# If:
#     The proportions are centered around 0.5,
#     The autocorrelations are centered around 0 with no outliers,
#     The runs test p-values are mostly > 0.05,
#     The global chi-squared test is non-significant,
#     And the entropy is near 1.0,
# → then you can confidently conclude that your sequences behave as expected for true random binary data.



