# galea — EEGLAB plugin for the Galea multimodal VR headset

Import and preprocess recordings from the Galea headset (OpenBCI), a dry-electrode
EEG system integrated into a Varjo Aero VR head-mounted display.

Standard EEGLAB import and cleaning routines assume a gel-based, high-density montage
and a nominal sampling rate. Galea recordings break three of those assumptions, and
this plugin handles each one.

## Install

Copy this folder into `eeglab/plugins/` and restart EEGLAB. A **Galea** entry
appears in the EEGLAB menu bar. It opens one window that does everything, top to
bottom: load a recording (step 1), then optionally process it (step 2), one
section per modality. For a fully worked example from raw file to ERP, see the
step-by-step tutorial with screenshots in the [repository README](../README.md)
or run the script [`tutorial_galea.m`](tutorial_galea.m) section by section.

## What it does

**`pop_galea_import`** reads the raw Galea file and

- splits the multiplexed streams into EEG, EOG, EMG, PPG, EDA and IMU, keeping the
  non-EEG streams in `EEG.etc.galea` rather than discarding them;
- derives the sampling rate from the device timestamps instead of the nominal rate
  (the effective rate is typically ~248 Hz, not the advertised 250 Hz, and the
  difference propagates into every latency and wavelet frequency downstream);
- supports both the stock 10-channel montage and the 12-channel custom montage in
  which the two EMG disc electrodes are reconfigured as Fp1/Fp2;
- converts the numeric trigger codes into readable event labels.

**`pop_galea_preprocess`** applies the steps that differ from a standard pipeline:

- a **minimum-phase causal** bandpass filter, so the pre-stimulus period cannot be
  contaminated by post-stimulus activity smeared backwards in time. This matters for
  any anticipation or pre-stimulus analysis, where the zero-phase filters applied by
  default in most software can manufacture effects that are entirely artefactual;
- **polarity correction for the prefrontal disc electrodes**, which the Galea
  amplifier sometimes records with inverted leads. Detection compares the sign of
  each suspect channel against a robust median reference at high-amplitude
  timepoints, where blinks provide a strong common-mode deflection;
- **bad-channel detection tuned for a sparse dry montage.** `clean_rawdata` assumes
  enough neighbouring channels for its correlation criterion to be meaningful; with
  12 electrodes it is unreliable. This uses a sliding-window combination of amplitude
  outliers and inter-channel correlation instead;
- artifact subspace reconstruction.

## Scripting

```matlab
EEG = pop_galea_import('montage', 'custom');
EEG = pop_galea_preprocess(EEG, 'locut', 0.5, 'hicut', 30, 'causal', true);
```

Both functions return an EEGLAB history string, so they work with `eegh` and in
batch scripts.

## Sample data

Two sample recordings ship in `sample_data/`:

- **`Sample-Data-OpenBCI-RAW.txt` (+ Aux)** — epoched ERP recording (subject sub-005,
  trials 1-98 of the collision study), for trying the full preprocessing pipeline.
- **`Sample-Data-OpenBCI-RAW-RestingState.txt` (+ Aux)** — 5.5-minute continuous
  resting-state recording (250 Hz, no markers), for trying the import on a
  continuous dataset. Imports cleanly with `pop_galea_import` and contains all
  streams (EEG, EOG, EMG, PPG, EDA, IMU).

## Also included

- `tutorial_galea.m` — the same walkthrough as the repository README's tutorial as a runnable script, seven sections, each with more parameter detail.
- `find_badTrials.m` — epoch rejection by amplitude and high-frequency residual, using
a mean-based outlier criterion.

## Citation

Cannard, C., & Yeşilbaş, D. (2026). *Reactive and predictive processes during
unpredictable driving hazards in virtual reality: an exploratory brain and body
study with multimodal neurophysiological monitoring.*

## License

See the parent repository.
