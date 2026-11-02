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

The vignette then rendered against that store in 38.5 minutes, reporting
`Precompiled without error` and writing all nine figures. Nothing is sampled in
those 38.5 minutes: they are `ecx()` and `nsec()` extraction across the 14- and
18-equation sets, which is the cost bayesnec #306 measured on `example7` and a
property of the vignette rather than of this arrangement.

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

## A joint refit

`bnec_joint()` refits a `bayesnecgroupfit` as one model with each curve
parameter given a value per level. What it is handed is not data but the object
an earlier call in the same vignette produced, so it sits outside the array in
two ways.

Its key is derived from the normalised call and from the key of the fit it
refits, rather than from a digest of `data`. The dependency is part of the
identity: a change to the `bnec_group()` call changes that call's key, and the
joint refit's key changes with it, so the render stops at the joint chunk rather
than loading a refit of the previous draft. The compendium reaches the
prerequisite's key by following the variable the call names back to the earlier
fit call in the vignette source; the shim reaches it by reading an attribute
that every object the store hands back is stamped with. Two routes to the same
string, which is what `analysis/check_keys.R` tests.

It is also not an array task. It needs its prerequisite fitted and then
reassembled, and no task in the units array can wait on another, so it runs in a
job of its own chained behind the assembly. `analysis/run_joint.R` reads the
prerequisite out of the store, binds it under the name the vignette assigned,
runs the vignette's own steps between the two calls -- `screen_models()` is the
one example8 applies -- and evaluates the joint call.

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

## Post-fit results

Reading every fit from the store does not by itself make the render quick. The
vignette's own calls on the fits rebuild model averages, recompute
leave-one-out criteria and compute posterior predictions over every draw of
every equation. With every fit read from `store-531`, a render took about six
hours on a workstation and on the cluster.

The calls were timed on a workstation on 2026-11-02, against `store-531` and
`bayesnec` 2.1.3.44 at `16e666dd`, one call at a time. On the two smallest sets,
`fit_plain` and `fit_ogl` (15 equations, 44 readings each), `screen_models()`
took 99 and 131 s, `summary()` 93 s, `ecx()` 91 and 121 s, `autoplot()` 76 and
104 s, and `pull_out()` of one equation 11 s. On `fit_cell` (15 equations, 748
readings, 615 MB on disk) `screen_models()` took 204 s, `summary()` 194 s,
`ecx()` 180 s and `pull_out()` 21 s, with a peak resident memory of 3.9 GB.
These two comparisons suggest that the time depends more on the number of
equations than on the number of readings. Most of the time `autoplot()` takes on
a model set is spent in a complete `summary()`, computed only to label the
no-effect line.

The compendium therefore computes these calls once, on the cluster, and writes
each result to `store/post/`. The shim answers the calls from there in the same
way it answers the fit calls, and the vignette's visible code is unchanged. The
calls answered are `screen_models()`, `summary()`, `check_sampling()`,
`pull_out()`, `ecx()`, `nsec()`, `nec()`, `rhat()`, `compare_posterior()` and
`autoplot()`, wherever the object they are handed came from the store.

A result is filed under a key derived from the key of the object the call is
handed, a digest of that object's weights and model list, the function, the
values of its other arguments, and the `bayesnec` version. The object's key is
the fit store's key, or the key of the post-fit call that returned it. For
example, `fit <- screen_models(fit)` followed by `summary(fit)` keys the summary
on the screened set. Each level of a `bnec_group()` fit is given a key of its own, so a
call on `fits_tox$fits[[1]]` is answered as well. A call on an object without a
key is run as written.

Each answered call is evaluated under a seed derived from its key, and the
render's random number stream is restored afterwards. `screen_models()` and
`summary()` both draw random numbers: the first redraws the pseudo-BMA-BB
weights of a rebuilt set, and the second draws the 200 posterior draws of its
control check. Without the seed, a result would depend on every chunk before
it, and no task in a session of its own could reproduce it. With it, a stored
result is the result the render would compute, whichever session computed it,
and a render that reads stored results produces the same output as one that
computes them. The model weights and other averaged quantities in a render with
the shim therefore differ from those of a render without it, in the way that a
change of seed changes them.

`hpc/run.post` submits one array task per stored object, with memory and time
set from the size of its file. Each task runs `analysis/run_post.R`, which runs
the vignette's code in order with only its own object read from the store.
Every other fit call is bound to a placeholder, an empty object with the stored
fit's key and none of its contents. Because the code runs in order, the calls
on one set run in the vignette's order within one task, while the tasks run in
parallel. A call on a
placeholder returns at once, with a value that most expressions can proceed
with. For example, an `rbind()` of the `ecx()` of two sets still evaluates the
second set's call in the second set's task. An expression that cannot
proceed stops at the placeholder, and the render job computes the calls left
unevaluated, records them in the store, and lists them in `post-log.tsv`.

The arrangement was tested on a workstation on 2026-11-02, against `store-531`
and `bayesnec` 2.1.3.44 at `16e666dd`, on a vignette of 68 of example8's 107
chunks: the sections on within-concentration grouping, the plate terms and the
herbicides with their joint refit, which use 11 of the 20 stored objects. One
`run_post.R` task per object, run three at a time beside other work, computed
100 calls in 229 minutes of task time; the longest task, `fit_plate`, took 46
minutes. The tasks made from 2 to 19 distinct calls on each object. The stored
results occupied 1.7 GB, of which 0.9 GB was five plots stored before the shim
was changed to force the promises in a plot's environment. Stored that way, a
plot takes 0.7 MB and the results would occupy 0.8 GB. A render of that vignette then read all 132 of its post-fit calls from the
store, computed none, and knitted in 74 s. Two parts of it were also knitted
with `BAYESNEC_POST_STORE=compute`, under which the shim computes every call in
the render's own session: the first 40 chunks (four sets, 17 calls) took 59.7 minutes against
28 s from the store, and the herbicide section (14 calls) 29.7 minutes against
15 s. In both, the knitted markdown and every figure were byte-identical to the
render that read the stored results. The full vignette and the cluster jobs
have not yet been run this way.

A call the store does not hold is computed and reported on standard error,
rather than stopping the render as a missing fit does. Its result is the same
wherever it is computed, and computing it takes minutes, where a missing fit
would take a day.

Two limits follow from the key. After a change to `bayesnec` that alters what
an answered function returns but not the version, the render still reads the
results stored before the change; delete `store/post/` when that happens and
resubmit `hpc/run.post`. And because the version is part of every key, the shim reads
stored results only under the version that computed them. `store/post/MANIFEST`
records that version, and the shim prints a message on a mismatch when it is
installed.

## Running it

```sh
cp hpc/local.conf.example hpc/local.conf   # gitignored; edit it
./hpc/deploy.sh                            # export, copy, submit
```

`deploy.sh` exports `bayesnec` at the ref `hpc/local.conf` names, records the
commit in `hpc/bayesnec.lock`, syncs both trees, copies the container if the
cluster does not already hold the one `hpc/image.lock` records, and submits.
`submit.sh` then chains five jobs, and the last of them submits the post-fit
array and the render:

| job | tasks | what it does |
|---|---|---|
| `run.install` | 1 | installs `bayesnec`, builds the manifest against the deployed vignette, and runs the key check as a gate |
| `run.units` | 189 | one equation each, on a dependency behind the gate |
| `run.assemble` | 1 | reassembles the nine objects and writes the store |
| `run.joint` | 1 | fits any `bnec_joint()` call from the assembled store |
| `run.post` | 1 | plans the post-fit array from the assembled store, and submits it and the render |
| `run.post-task` | one per stored object | the vignette's post-fit calls on one object, written to `store/post/` |
| `run.render` | 1 | renders example8 from the store, computing and recording any post-fit call the array did not reach |

`run.post` submits the array because the memory each task needs is read from
the assembled store, which does not exist when `submit.sh` runs. It submits one
array per memory class in `store/post/classes.txt`, and the render behind all of
them. For a store that is already assembled, the last three run on their own:

```sh
sbatch --export=ALL,GRP_STORE=<store> hpc/run.post
```

The arrays are idempotent: a unit whose file exists is skipped, and a post-fit
result already stored is read back, not recomputed, so a timed-out subset is
recovered by resubmitting the same job.

Bring the store back, with its post-fit results, and point a render at it:

```sh
GRP_STORE=<store> ./hpc/fetch-store.sh
export BAYESNEC_FIT_STORE=$PWD/<store>
```

The render reads `<store>/post/` without further setting. With
`BAYESNEC_POST_STORE=compute` the shim computes every post-fit call instead, and
with `BAYESNEC_POST_STORE=off` it leaves them to `bayesnec`. Whenever `shim/fit_store.R`
has been regenerated, copy it to `bayesnec/vignettes/fit_store.R` before the
render.

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
| `R/keys.R` | the keys a fit and a post-fit result are filed under; copied verbatim into the shim |
| `R/vignette.R` | reading the fit calls out of the vignette, and rebuilding what they are given |
| `R/units.R` | splitting a call into units, and running one |
| `R/assemble.R` | putting the units back into a `bayesmanecfit` or a `bayesnecgroupfit` |
| `analysis/build_manifest.R` | every fit call, split into units; writes `manifest.rds` |
| `analysis/check_keys.R` | the gate: the shim must ask for the manifest's keys |
| `analysis/run_unit.R` | fit one unit |
| `analysis/assemble_store.R` | assemble the store |
| `analysis/run_joint.R` | fit the joint refits, after the store is assembled |
| `analysis/plan_post.R` | one post-fit task per stored object, sized to its file; writes `store/post/tasks.csv` |
| `analysis/run_post.R` | the vignette's post-fit calls on one stored object, written to `store/post/` |
| `analysis/build_shim.R` | generate `shim/fit_store.R` for copying into `bayesnec` |
| `shim/fit_store.R` | generated; belongs in `bayesnec/vignettes/` |
