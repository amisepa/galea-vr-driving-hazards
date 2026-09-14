# Galea VR collision study

Pre- and post-stimulus neurophysiology of unpredictable car collisions in immersive virtual
reality, recorded with the Galea multimodal headset (OpenBCI) integrated into a Varjo Aero HMD.

Cannard, C., & Yeşilbaş, D. (2026). *Post-stimulus, but not pre-stimulus, neural differentiation
of unpredictable car collisions in immersive virtual reality: an exploratory study with a novel
wearable multimodal headset.* Supported by the BIAL Foundation. Preregistered at
[osf.io/xuw34](https://osf.io/xuw34).

## Layout

| Folder | Contents |
|---|---|
| `pipeline/` | Per-subject preprocessing. `galea_pipeline_v6_EEG.m` is current; `functions/` holds the Galea-specific helpers (import, event renaming, polarity correction, bad-channel detection). `galea_pipeline_v5_ppg.m` produces the per-subject heart-rate exports (`ERP_PPG.mat`) the cardiac analysis reads. |
| `analysis/` | Group-level analyses. Everything named `run_final_*` operates on the repaired dataset and writes to `results_final/`. |
| `manuscript/` | `build_manuscript.js` generates the .docx from the result files, plus the current draft and the earlier versions. |
| `results_final/` | Output of the current analyses. Superseded folders were removed; they are archived in the study's Proton Drive archive (`code_archive/results_superseded/`). |
| `data/` | `stim_sequences_delivered/` (the quantum-randomised 120-trial sequence actually delivered to each subject, copied from the acquisition drive), the exported classification dataset, and `random_stim_sequences/` (sequence-generation code and diagnostics). |
| `galea_eeglab_plugin/` | EEGLAB plugin for importing and preprocessing Galea recordings, with an ERP sample dataset and a continuous resting-state sample in `sample_data/`. |

Study data (raw recordings, per-subject exports), grant/admin documents, the Unity VR program and archived code live on Proton Drive under
`DATA/IONS_Galea_VR_study/` (`study_data/`, `grant_admin/`, `unity_vr_program/`, `code_archive/`).

## Reproducing the analyses

Run in this order. All scripts are self-contained and write to `results_final/`.

```matlab
pipeline/fix_sub011_erp_export.m      % one-off data repair (already applied)
pipeline/galea_pipeline_v5_ppg.m      % per-subject heart-rate exports for the cardiac analysis
analysis/rerun_final_stats.m          % time-domain GLM + permutations (supersedes the four earlier ERP/cluster scripts)
analysis/run_final_EEG_tf_causal.m    % time-frequency, both normalisations
analysis/run_final_EEG_alday.m        % baseline-regressor sensitivity analysis
analysis/run_final_EEG_covariates.m   % exploratory moderator models
analysis/galea_group_analysis_PPG.m   % cardiac analysis
analysis/make_figures.m               % manuscript figures
```

Then rebuild the manuscript:

```bash
node manuscript/build_manuscript.js
```

Every reported number is read from the result files at build time rather than transcribed, and
the builder refuses to run if any analysis is incomplete.

## Two things worth knowing

**The sub-011 repair.** That participant's session was interrupted and recorded as two files.
Both `.mat` exports ended up containing the same short second session, so the subject entered
every EEG analysis as duplicated trials. `pipeline/fix_sub011_erp_export.m` rebuilds both from
the surviving epoched `.set` files, giving 53 collision / 35 no-collision unique trials. All
results here postdate that repair; results computed before it were discarded.

**`compute_mcc_fast.m`.** The cluster-correction routine in `eeg_robust_statistics` computes
cluster masses with a loop that is O(clusters × elements). That is fine on post-stimulus data,
which has a few large clusters, but a noise-like map produces thousands of tiny ones and it
stalls indefinitely — which affects the pre-stimulus window and most covariate models.
`analysis/compute_mcc_fast.m` is a drop-in replacement using `accumarray`, verified to give
identical output on the post-stimulus window.

## Dependencies

MATLAB (R2026a used here) with EEGLAB, plus
[eeg_robust_statistics](https://github.com/amisepa/eeg_robust_statistics),
[Ascent](https://github.com/amisepa/Ascent) (aperiodic fitting, no Python needed),
[BrainBeats](https://github.com/amisepa/BrainBeats) (heartbeat detection), and
[Robust-Correlations](https://github.com/amisepa/Robust-Correlations) (H4 time-symmetry analysis).
Node.js with `docx` for the manuscript builder.

All script paths are configured in one place: edit the four defaults at the top of
`galea_set_paths.m` (EEGLAB, the two toolboxes, and the study data folder) and every
analysis and pipeline script picks them up.

## License

GPL-3.0 — the same licence as [eeg_robust_statistics](https://github.com/amisepa/eeg_robust_statistics),
[Ascent](https://github.com/amisepa/Ascent) and [BrainBeats](https://github.com/amisepa/BrainBeats),
which this pipeline depends on. Academic use is unaffected; anyone redistributing the code
(including commercial users) must release their modifications under the same terms.
