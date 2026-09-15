# grouping-structures

The fits behind the *Grouping and factor covariates* vignette (`example8`) in
[`bayesnec`](https://github.com/open-AIMS/bayesnec), run as independent cluster
tasks and stored so that the vignette can be built without fitting anything.

## Background

`example8` fits 189 models: five model-averaged sets over the whole candidate
list, two deliberate two-equation contrasts, and two `bnec_group()` calls that
fit a complete set at each of seven and two levels. Run in sequence on the four
cores a precompile job asks for, that is the better part of a day — longer than
the walltime, and far longer than a vignette should take to rebuild after a
prose correction.

Every one of those 189 fits is independent of every other. This repository runs
each as its own array task, reassembles them into the nine objects the vignette
expects, and writes them to a store. The precompile then reads the store. The
sampling happens once, on the cluster, and a prose edit is a render rather
than a day.

Measured on the AIMS HPC on 2026-09-16, against `bayesnec` at `5f98d8d6`, with
40 tasks resident: the 189 units hold 22.2 hours of fitting between them, and the
array ran from 01:36 to 02:28 --- 52 minutes. The median unit took 1.3 minutes
and the slowest 36.2, which is the floor the array width cannot go below. Six
units failed, all of them `ecxhormebc5`, which is the initial-value problem of
bayesnec #344 rather than something a re-run fixes; they are recorded as failed
and their sets averaged over the equations that did fit, which is what `bnec()`
does with a model it cannot fit. The store is 484 MB.

## Agreement between the vignette and the store

Nothing here restates any of the vignette's code.

The fit calls are read out of `example8.Rmd.orig` itself. The data each one is
handed is built by running the vignette's own preparation chunks up to that
point. A fit is filed under a key derived from the call and from a digest of the
data, and the same key is computed a second time, independently, by the shim
that answers the call during the render.

That is the whole contract, and it fails loudly. A vignette edit that changes a
fit call changes its key; the render finds nothing under the new key and stops at
that chunk. It cannot load the fit that belonged to the previous draft, and it
cannot quietly start sampling for a day instead.

`analysis/check_keys.R` tests the contract without fitting anything: it stands up
a store of empty files under the manifest's keys, installs the shim, and runs the
vignette. Every fit call must resolve. The cluster job runs it as a gate before
any sampling starts.

## The unit of work

One unit is one equation of one model set, on one level where the call is a
`bnec_group()` one. That is the finest grain `bayesnec` can be reassembled at:
`expand_manec()` builds a `bayesmanecfit` from separately fitted equations, and a
`bayesnecgroupfit` is a list of per-level fits. The 189 units divide as:

| call | units |
|---|---|
| `fit_plain`, `fit_ogl`, `fit_pooled`, `fit_plate` | 15 each |
| `fit_pam` | 18 |
| `three_par`, `four_par` | 2 each |
| `fits_herb` | 77 (7 herbicides × 11 equations) |
| `fits_tox` | 30 (2 toxicants × 15 equations) |

A call that cannot be decomposed runs whole, as one task. It is still fitted in
parallel with every other call; it simply does not divide further.

## The route back to a model average

`R/assemble.R` reaches `expand_manec()` directly, which is the call `bnec()`
itself makes, rather than going through the exported `c.bnecfit()`.

`c.bnecfit()` was the obvious route and it does not work here. It runs
`check_data_equality()`, which compares `as.matrix(fit$data)` between fits with
`identical()`. `brms` orders those columns by the model formula, and the hormesis
equations put the predictor before the grouping factor where the others put it
after: on `fit_pam` the five hormesis equations came back with
`yield, diuron, chamber` against the other thirteen's `yield, chamber, diuron`.
Every value is the same and every column is the same; only the order differs, and
`identical()` is order-sensitive, so the combination was refused. A monolithic
`bnec()` never meets that check, because it hands its `prebayesnecfit` list
straight to `expand_manec()`. Reported as bayesnec #361.

The substitution was checked against a set `c()` could combine: `three_par`, two
equations on `coral_colour`, combined from the same two unit files by both
routes, gives weights of 0.5487 and 0.4513 and an EC10 of 4.0972
(2.7831--10.9813) to every digit either way.

Two things `c.bnecfit()` does that this route must therefore do for itself.
`attach_failed_models()` records an equation that could not be fitted, which is
what `failed_models()` reads. `attach_bnec_record()` records the candidate set as
requested against the set as attempted; without it an assembled object reports
whichever unit came first, so a fit whose call said `"all"` would report
`requested = "ecxll3"`.

## The scope of an assembled set

Each equation is identical to the one a single `bnec()` call would have produced:
a unit passes the vignette's own `seed` through to `brm()`, so the equation
samples from the same stream whether it was fitted alone or eighteenth in a set.

The model-averaged layer is not identical. `expand_manec()` draws from the
session's random number stream to build the averaged prediction grid, and a
session that has just fitted seventeen other equations is at a different point in
that stream than one that has fitted none. `bayesnec` documents the same thing
for its own parallel model loop, under *Fitting a model set in parallel*: the
averaged quantities are not reproduced between a sequential and a parallel run
even with a seed. `ASSEMBLY_SEED` in `R/assemble.R` is set immediately before
each combination, which does not make the result equal to a monolithic run but
does make this one repeatable.

## Running it

```sh
cp hpc/local.conf.example hpc/local.conf   # gitignored; edit it
./hpc/deploy.sh                            # export, copy, submit
```

`deploy.sh` exports `bayesnec` at the ref `hpc/local.conf` names, records the
commit in `hpc/bayesnec.lock`, syncs both trees, copies the container if the
cluster does not already hold the one `hpc/image.lock` records, and submits.
`submit.sh` then chains three jobs:

| job | tasks | what it does |
|---|---|---|
| `run.install` | 1 | installs `bayesnec`, builds the manifest against the deployed vignette, and runs the key check as a gate |
| `run.units` | 189 | one equation each, on a dependency behind the gate |
| `run.assemble` | 1 | reassembles the nine objects and writes the store |

The array is idempotent: a unit whose file exists is skipped, so a timed-out
subset is recovered by resubmitting the same array.

Bring the store back and point a render at it:

```sh
./hpc/fetch-store.sh
export BAYESNEC_FIT_STORE=$PWD/store
```

## The container

The study runs inside the image built by the `bayesnec` repository,
`hpc/bayesnec-precompile.def`, which holds R, cmdstan, `brms` and the packages
the vignette loads, and deliberately does not hold `bayesnec`. The job installs
`bayesnec` from the pinned source at start-up, so one image serves both
repositories and every branch. `hpc/image.lock` is a committed copy of the
identity that build writes, and every job refuses to run against an image whose
SHA does not match it.

The same arrangement, and the same reasoning, as
[`negative-response-conventions`](https://github.com/open-AIMS/negative-response-conventions),
the compendium behind `example7`. The one deliberate difference is the Stan
program cache, which is per-task here rather than shared between tasks:
`bayesnec` derives its priors from the response and `brms` writes them into the
Stan source as literals, so with every unit on different data there is almost
nothing for a shared cache to reuse — and a shared cache would let two tasks run
`make` on the same executable path at the same time. `hpc/job-common.sh` records
this.

## Files

| file | what it is |
|---|---|
| `R/keys.R` | the key a fit is filed under; copied verbatim into the shim |
| `R/vignette.R` | reading the fit calls out of the vignette, and rebuilding what they are given |
| `R/units.R` | splitting a call into units, and running one |
| `R/assemble.R` | putting the units back into a `bayesmanecfit` or a `bayesnecgroupfit` |
| `analysis/build_manifest.R` | every fit call, split into units; writes `manifest.rds` |
| `analysis/check_keys.R` | the gate: the shim must ask for the manifest's keys |
| `analysis/run_unit.R` | fit one unit |
| `analysis/assemble_store.R` | assemble the store |
| `analysis/build_shim.R` | generate `shim/fit_store.R` for copying into `bayesnec` |
| `shim/fit_store.R` | generated; belongs in `bayesnec/vignettes/` |
