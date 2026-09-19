# grouping-structures notes

Project-specific context, additional to `C:/Rworking/CLAUDE.md`. That file's
conventions apply here; this one records only what is particular to this
repository.

## Repo type

A research compendium, not a package. There is no `DESCRIPTION`, no `R CMD
check` and no GitHub Actions. `::: ` is used where a script has to mirror
something `bayesnec` does internally, and a comment says which function it
mirrors and why a parallel implementation would be wrong.

The packages in use are `bayesnec`, `brms`, `digest`, and whatever `example8`
itself attaches. The container `hpc/image.lock` records is the canonical list;
anything not in it has to go into `bayesnec/hpc/bayesnec-precompile.def` and the
image rebuilt.

## The rule against restating vignette code

Nothing here restates any of the vignette's code. The fit calls are read out of
`example8.Rmd.orig`, and the data each is handed is built by running the
vignette's own preparation chunks. A copy of either kept here would be a second
thing to maintain and a silent way for the store to be built against data the
vignette does not use.

The check is mechanical rather than remembered. `analysis/check_keys.R` installs
the shim against a store of empty files and runs the vignette; every fit call
must resolve to a key the manifest planned units for. `hpc/run.install` runs it
as a gate before anything samples.

## After a vignette edit

Rebuild the manifest and re-check the keys. A key changes when its call changes, and
a store built against an older draft is a store the render refuses.

```sh
Rscript analysis/build_manifest.R <path>/example8.Rmd.orig
Rscript analysis/check_keys.R
```

Only the units whose keys changed need refitting; `run_unit.R` skips a unit whose
file exists, so resubmitting the whole array fits exactly the ones that changed.

## A joint refit is keyed on its prerequisite

`bnec_joint()` takes a fitted object rather than data, so its key is the
normalised call plus the key of the fit it refits. `R/keys.R` names those
functions in `FIT_FUNS_ON_FIT` and gives them `joint_key()` in place of
`fit_key()`; `object` is dropped from the deparsed arguments the way `data`
already is.

The two sides reach the prerequisite's key by different routes.
`analysis/build_manifest.R` follows the variable the call names back to the
earlier fit call that assigned it, and refuses by name where there is none. The
shim reads an attribute, `fit_store_key`, which it stamps on every object it
returns.

The key covers the two calls and not the code between them. A `bnec_joint()`
call written after the `screen_models()` chunk that rebinds its prerequisite
refits a different object and keys to the same string as one written before it,
so the render would load a refit of the other object without saying so.
`analysis/run_joint.R` closes that by binding the stored fit under the name its
own call assigned *before* running the vignette prefix, so every step between
the two calls runs on it there as it will at the render. Measured on the
herbicide fit on 2026-09-19: refitting after `screen_models()` sees ten
equations on simazine against the stored object's eleven, and both placements
key to `38664a5ef3349e77`.

A joint refit is not an array task. It needs its prerequisite fitted and then
reassembled, and nothing in the units array can wait on another task, so it runs
from `analysis/run_joint.R` in `hpc/run.joint`, chained behind `hpc/run.assemble`.
`assemble_store.R` skips it and rewrites `index.csv` without it; `run_joint.R`
adds its row back.

## The shim is generated

`shim/fit_store.R` is written by `analysis/build_shim.R` from `R/keys.R` and
`shim/fit_store_body.R`, and copied into `bayesnec/vignettes/`. Edit the sources,
regenerate, and copy. The generated file records the digest of `R/keys.R` it was
built from, so a copy in `bayesnec` that has fallen behind can be detected.

## Traps carried over from the example7 compendium

A stale `lib/` in the repository root shadows whatever library a script is run
against, silently. `.Rprofile` prepends it only when it exists, and the jobs
assert that the `bayesnec` they loaded came from the job library at the version
`hpc/bayesnec.lock` names. Check which `bayesnec` you have before running
anything here by hand.

`sbatch` is not on `PATH` in a non-interactive shell on this cluster. A plain
`ssh host ./hpc/submit.sh` submits nothing unless `module load slurm` has run
first, which `submit.sh` does.

## Naming the models in prose

Section 12 rule 6 of the global file, and `bayesnec/CLAUDE.md` for the specifics.
`bayesnec` has 23 model equations and ten of them are NEC models, so "the nec
model" never identifies one: name `nec3param`, `nec4param` or `ecxll3`.
`bayesnec` and `brms` are packages; `bnec()`, `bnec_group()` and `brm()` are
functions.
